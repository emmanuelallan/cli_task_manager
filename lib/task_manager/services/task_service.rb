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
require_relative '../notifications/email_sender'

module TaskManager
  module Services
    # handles task management operations
    class TaskService
      attr_reader :current_user_id

      # sets up service
      def initialize
        @current_user_id = nil
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

        tasks
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
        update_task(id, status: 'completed', completed_at: Time.now)
      end

      # marks task as pending
      # @param id [String] task identifier
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      def reopen_task(id)
        update_task(id, status: 'pending', completed_at: nil)
      end

      # deletes task
      # @param id [String] task identifier
      # @raise [TaskNotFoundError] if task not found
      def delete_task(id)
        task = find_task_by_id(id)
        task.destroy
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
    end
  end
end