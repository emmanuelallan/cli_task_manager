# lib/task_manager/services/task_service.rb
require 'securerandom'
require 'csv'

require_relative '../models/task'
require_relative '../persistence/database_store'
require_relative '../core/errors'
require_relative '../strategies/filtering/tag_filter_strategy'
require_relative '../strategies/filtering/due_date_filter_strategy'
require_relative '../strategies/sorting/due_date_sort_strategy'
require_relative '../strategies/sorting/priority_sort_strategy'
require_relative '../notifications/notifier'
require_relative '../notifications/system_notifier'

module TaskManager
  module Services
    # handles task management operations
    class TaskService
      attr_reader :current_user_id, :notifier, :logger

      # sets up service with notification system
      def initialize
        @current_user_id = nil
        @notifier = TaskManager::Notifications::Notifier.new
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [TaskService] #{msg}\n"
        end
        
        # Add system notifier as observer
        system_notifier = TaskManager::Notifications::SystemNotifier.new
        @notifier.add_observer(system_notifier)
      end

      # sets current user id for task operations
      # @param user_id [String] user identifier
      def set_current_user_id(user_id)
        @current_user_id = user_id
      end

      # creates new task
      # @param attributes [Hash] task attributes
      # @return [Task] new task
      # @raise [InvalidInputError] if task creation fails
      def add_task(attributes)
        task = TaskManager::Models::Task.new(
          id: SecureRandom.uuid,
          user_id: @current_user_id,
          **attributes
        )

        if task.save
          notify_task_event(task, :task_created)
          task
        else
          raise TaskManager::InvalidInputError, "failed to create task: #{task.errors.full_messages.join(', ')}"
        end
      end

      # finds task by id
      # @param id [String] task identifier
      # @return [Task] matching task
      # @raise [TaskNotFoundError] if task not found
      def find_task_by_id(id)
        task = TaskManager::Models::Task.find_by(id: id, user_id: @current_user_id)
        raise TaskManager::TaskNotFoundError, "task '#{id}' not found" unless task
        task
      end

      # lists tasks with optional filters
      # @param filters [Hash] filter options
      # @return [Array<Task>] filtered tasks
      def list_tasks(filters = {})
        tasks = TaskManager::Models::Task.where(user_id: @current_user_id)

        # Apply filters
        tasks = tasks.where(status: filters[:status]) if filters[:status]
        tasks = tasks.where('tags LIKE ?', "%#{filters[:tag]}%") if filters[:tag]
        tasks = tasks.where('due_date < ?', Date.today) if filters[:overdue]

        # Apply sorting
        if filters[:sort_by]
          case filters[:sort_by]
          when 'due_date'
            tasks = tasks.order(due_date: :asc)
          when 'priority'
            tasks = tasks.order(priority: :desc)
          when 'created_at'
            tasks = tasks.order(created_at: :desc)
          end
        end

        tasks.to_a
      end

      # updates task attributes
      # @param id [String] task identifier
      # @param attributes [Hash] new attribute values
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      # @raise [InvalidInputError] if update fails
      def update_task(id, attributes)
        task = find_task_by_id(id)
        
        if task.update(attributes)
          notify_task_event(task, :task_updated)
          task
        else
          raise TaskManager::InvalidInputError, "failed to update task: #{task.errors.full_messages.join(', ')}"
        end
      end

      # marks task as completed
      # @param id [String] task identifier
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      def complete_task(id)
        task = update_task(id, status: 'completed', completed_at: Time.now)
        notify_task_event(task, :task_completed)
        task
      end

      # marks task as pending
      # @param id [String] task identifier
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      def reopen_task(id)
        task = update_task(id, status: 'pending', completed_at: nil)
        notify_task_event(task, :task_reopened)
        task
      end

      # deletes task
      # @param id [String] task identifier
      # @raise [TaskNotFoundError] if task not found
      def delete_task(id)
        task = find_task_by_id(id)
        task.destroy
        notify_task_event(task, :task_deleted)
      end

      # checks for overdue tasks and sends notifications
      def check_overdue_tasks
        overdue_tasks = TaskManager::Models::Task.where(
          user_id: @current_user_id,
          status: 'pending'
        ).where('due_date < ?', Date.today)

        overdue_tasks.each do |task|
          notify_task_event(task, :task_overdue_check)
        end

        overdue_tasks.to_a
      end

      # checks for tasks due soon and sends notifications
      def check_due_soon_tasks
        due_soon_tasks = TaskManager::Models::Task.where(
          user_id: @current_user_id,
          status: 'pending'
        ).where('due_date BETWEEN ? AND ?', Date.today, Date.today + 1)

        due_soon_tasks.each do |task|
          notify_task_event(task, :task_due_soon)
        end

        due_soon_tasks.to_a
      end

      # exports tasks to file
      # @param format [Symbol] export format (e.g., :csv)
      # @param filename [String] output file path
      # @raise [InvalidInputError] if format not supported
      # @raise [FileError] if file operations fail
      def export_tasks(format:, filename:)
        tasks = list_tasks

        case format
        when :csv
          CSV.open(filename, 'w') do |csv|
            csv << ['ID', 'Title', 'Description', 'Status', 'Due Date', 'Tags', 'Priority', 'Created At', 'Completed At']
            tasks.each do |task|
              csv << [
                task.id,
                task.title,
                task.description,
                task.status,
                task.due_date&.strftime('%Y-%m-%d'),
                task.tags.join(','),
                task.priority,
                task.created_at.strftime('%Y-%m-%d %H:%M:%S'),
                task.completed_at&.strftime('%Y-%m-%d %H:%M:%S')
              ]
            end
          end
        else
          raise TaskManager::InvalidInputError, "unsupported export format: #{format}"
        end
      end

      # imports tasks from file
      # @param format [Symbol] import format (e.g., :csv)
      # @param filename [String] input file path
      # @raise [InvalidInputError] if format not supported
      # @raise [FileError] if file operations fail
      def import_tasks(format:, filename:)
        case format
        when :csv
          CSV.foreach(filename, headers: true) do |row|
            add_task(
              title: row['Title'],
              description: row['Description'],
              status: row['Status'],
              due_date: row['Due Date'],
              tags: row['Tags'].to_s.split(','),
              priority: row['Priority'],
              created_at: Time.parse(row['Created At']),
              completed_at: row['Completed At'] ? Time.parse(row['Completed At']) : nil
            )
          end
        else
          raise TaskManager::InvalidInputError, "unsupported import format: #{format}"
        end
      end

      private

      # notifies observers of task events
      # @param task [Task] task that triggered the event
      # @param event_type [Symbol] type of event
      def notify_task_event(task, event_type)
        begin
          @notifier.update(task, event_type)
        rescue => e
          @logger.error("Notification failed for event #{event_type}: #{e.message}")
        end
      end
    end
  end
end