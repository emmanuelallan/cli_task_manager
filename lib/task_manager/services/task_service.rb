# lib/task_manager/services/task_service.rb
require 'securerandom'
require 'csv'

require_relative '../models/task'
require_relative '../persistence/file_store'
require_relative '../core/errors'
require_relative '../strategies/filtering/tag_filter_strategy'
require_relative '../strategies/filtering/due_date_filter_strategy'
require_relative '../strategies/sorting/due_date_sort_strategy'
require_relative '../strategies/sorting/priority_sort_strategy'
require_relative '../notifications/notifier'
require_relative '../notifications/email_sender'

module TaskManager
  module Services
    # manages task operations and persistence
    class TaskService
      attr_reader :file_store, :notifier
      attr_accessor :tasks, :current_user_id

      # sets up service with storage and user context
      # @param file_store [FileStore] storage handler
      # @param current_user_id [String, nil] active user id
      def initialize(file_store:, current_user_id: nil)
        @file_store = file_store
        @tasks = @file_store.load_tasks
        @current_user_id = current_user_id
        
        @notifier = TaskManager::Notifications::Notifier.new
        dummy_email_service = Object.new
        @notifier.add_observer(TaskManager::Notifications::EmailSender.new(dummy_email_service))
      end

      # sets current user context
      # @param user_id [String] user identifier
      def set_current_user_id(user_id)
        @current_user_id = user_id
      end

      # creates new task for current user
      # @param description [String] task details
      # @param due_date [String, Date, nil] when task is due
      # @param tags [Array<String>] task labels
      # @return [Task] new task
      # @raise [InvalidInputError] if no user set
      def add_task(description:, due_date: nil, tags: [], priority: nil, recurrence: nil, parent_task_id: nil)
        validate_current_user_set!

        new_id = generate_next_task_id
        parsed_due_date = due_date.is_a?(String) ? Date.parse(due_date) : due_date

        task = TaskManager::Models::Task.new(
          id: new_id,
          user_id: @current_user_id,
          description: description,
          due_date: parsed_due_date,
          tags: Array(tags),
          priority: priority,
          recurrence: recurrence,
          parent_task_id: parent_task_id
        )

        @tasks << task
        save_all_tasks
        task
      rescue ArgumentError => e
        raise TaskManager::InvalidInputError, "invalid due date format: #{e.message}"
      end

      # retrieves filtered and sorted tasks
      # @param options [Hash] filter and sort settings
      # @return [Array<Task>] matching tasks
      def list_tasks(options = {})
        validate_current_user_set!
        
        filtered_tasks = get_user_tasks(@current_user_id)
        
        if options[:tag]
            tag_strategy = TaskManager::Strategies::Filtering::TagFilterStrategy.new(options[:tag])
            filtered_tasks = tag_strategy.filter(filtered_tasks)
        end

        if options.key?(:completed)
            filtered_tasks = filtered_tasks.select { |task| task.completed == options[:completed] }
        end
        
        if options.key?(:overdue)
            filtered_tasks = filtered_tasks.select { |task| task.overdue? }
        end

        if options[:due_before] || options[:due_after] || options[:due_on]
            date_filter_options = {
                before: options[:due_before],
                after: options[:due_after],
                on: options[:due_on]
            }
            date_strategy = TaskManager::Strategies::Filtering::DueDateFilterStrategy.new(date_filter_options)
            filtered_tasks = date_strategy.filter(filtered_tasks)
        end

        case options[:sort_by]&.to_sym
        when :due_date
            sort_strategy = TaskManager::Strategies::Sorting::DueDateSortStrategy.new
            filtered_tasks = sort_strategy.sort(filtered_tasks)
        when :priority
            sort_strategy = TaskManager::Strategies::Sorting::PrioritySortStrategy.new
            filtered_tasks = sort_strategy.sort(filtered_tasks)
        else
            filtered_tasks = filtered_tasks.sort
        end

        filtered_tasks
      end

      # marks task as complete
      # @param task_id [String] task identifier
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      def complete_task(task_id)
        task = find_task_by_id_for_current_user(task_id)
        task.complete!
        save_all_tasks
        @notifier.update(task, :task_completed)
        task
      end

      # reopens completed task
      # @param task_id [String] task identifier
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      def reopen_task(task_id)
        task = find_task_by_id_for_current_user(task_id)
        task.reopen!
        save_all_tasks
        @notifier.update(task, :task_reopened)
        task
      end

      # removes task from storage
      # @param task_id [String] task identifier
      # @return [Boolean] true if successful
      # @raise [TaskNotFoundError] if task not found
      def delete_task(task_id)
        task = find_task_by_id_for_current_user(task_id)
        @tasks.delete_if { |t| t.id == task.id }
        save_all_tasks
        true
      end

      # retrieves task by id
      # @param task_id [String] task identifier
      # @return [Task] matching task
      # @raise [TaskNotFoundError] if task not found
      def find_task_by_id(task_id)
        find_task_by_id_for_current_user(task_id)
      end

      # updates task attributes
      # @param task_id [String] task identifier
      # @param attributes [Hash] new values
      # @return [Task] updated task
      # @raise [TaskNotFoundError] if task not found
      # @raise [InvalidInputError] if values invalid
      def update_task(task_id, attributes)
        task = find_task_by_id_for_current_user(task_id)
        old_completed_status = task.completed

        begin
          task.update(attributes)
          save_all_tasks
          if attributes.key?(:completed) && old_completed_status != task.completed
            event_type = task.completed ? :task_completed : :task_reopened
            @notifier.update(task, event_type)
          end
          task
        rescue ArgumentError => e
          raise TaskManager::InvalidInputError, "failed to update task: #{e.message}"
        end
      end

      # checks and notifies for overdue tasks
      def check_for_overdue_tasks
        get_user_tasks(@current_user_id).each do |task|
          if task.overdue? && !task.completed
            @notifier.update(task, :task_overdue_check)
          end
        end
      end

      # exports tasks to file
      # @param format [Symbol] output format
      # @param filename [String] target file
      # @raise [InvalidInputError] if format invalid
      def export_tasks(format:, filename:)
        validate_current_user_set!
        user_tasks = get_user_tasks(@current_user_id)

        case format
        when :csv
          CSV.open(filename, 'wb') do |csv|
            csv << ['ID', 'Description', 'Due Date', 'Tags', 'Completed', 'Created At', 
                   'Completed At', 'Priority', 'Recurrence', 'Parent Task ID']
            user_tasks.each do |task|
              csv << [
                task.id,
                task.description,
                task.due_date&.iso8601,
                task.tags.join(', '),
                task.completed,
                task.created_at.iso8601,
                task.completed_at&.iso8601,
                task.priority,
                task.recurrence.is_a?(Hash) ? task.recurrence.to_json : task.recurrence,
                task.parent_task_id
              ]
            end
          end
        else
          raise TaskManager::InvalidInputError, "unsupported export format: #{format}"
        end
      rescue => e
        raise TaskManager::FileError, "failed to export tasks: #{e.message}"
      end

      # imports tasks from file
      # @param format [Symbol] input format
      # @param filename [String] source file
      # @raise [InvalidInputError] if format invalid
      def import_tasks(format:, filename:)
        validate_current_user_set!
        raise TaskManager::FileError, "import file not found: #{filename}" unless File.exist?(filename)

        case format
        when :csv
          imported_count = 0
          CSV.foreach(filename, headers: true) do |row|
            task_attributes = {
              id: generate_next_task_id,
              user_id: @current_user_id,
              description: row['Description'],
              due_date: row['Due Date'],
              tags: row['Tags']&.split(', ')&.map(&:strip),
              completed: row['Completed'] == 'true',
              created_at: row['Created At'] ? Time.parse(row['Created At']) : Time.now,
              completed_at: row['Completed At'] ? Time.parse(row['Completed At']) : nil,
              priority: row['Priority'],
              recurrence: row['Recurrence'] ? JSON.parse(row['Recurrence']) : nil,
              parent_task_id: row['Parent Task ID']
            }.compact

            begin
              task = TaskManager::Models::Task.new(**task_attributes)
              @tasks << task
              imported_count += 1
            rescue ArgumentError => e
              puts "warning: skipping task import due to invalid data: #{row.to_h} - #{e.message}"
            end
          end
          save_all_tasks
        else
          raise TaskManager::InvalidInputError, "unsupported import format: #{format}"
        end
      rescue CSV::MalformedCSVError => e
        raise TaskManager::FileError, "malformed csv file: #{e.message}"
      rescue => e
        raise TaskManager::FileError, "failed to import tasks: #{e.message}"
      end

      # persists tasks to storage
      def save_all_tasks
        @file_store.save_tasks(@tasks)
      end

      private

      # generates unique task id
      # @return [String] uuid
      def generate_next_task_id
        SecureRandom.uuid
      end

      # gets tasks for specific user
      # @param user_id [String] user identifier
      # @return [Array<Task>] user's tasks
      def get_user_tasks(user_id)
        @tasks.select { |task| task.user_id == user_id }
      end

      # finds user's task by id
      # @param task_id [String] task identifier
      # @return [Task] matching task
      # @raise [TaskNotFoundError] if not found
      def find_task_by_id_for_current_user(task_id)
        validate_current_user_set!
        task = get_user_tasks(@current_user_id).find { |t| t.id == task_id }
        unless task
          raise TaskManager::TaskNotFoundError, "task not found: #{task_id}"
        end
        task
      end

      # ensures user is set
      # @raise [InvalidInputError] if no user
      def validate_current_user_set!
        unless @current_user_id
          raise TaskManager::InvalidInputError, "no user logged in"
        end
      end
    end
  end
end