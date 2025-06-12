# lib/task_manager/cli.rb
require 'thor'
require 'tty-prompt'
require 'colorize'
require 'logger'

require_relative 'services/user_service'
require_relative 'services/task_service'
require_relative 'models/task'
require_relative 'models/user'
require_relative 'core/errors'
require_relative 'config/application_config'

module TaskManager
  # handles command line interface and user interactions
  class CLI < Thor
    attr_accessor :current_user

    # sets up cli with required services
    # @param args [Array] thor arguments
    def initialize(*args)
      super
      app_config = TaskManager::Config::ApplicationConfig.instance
      
      @file_store = Persistence::FileStore.new
      @user_service = Services::UserService.new(file_store: @file_store)
      @task_service = Services::TaskService.new(file_store: @file_store)
      @prompt = TTY::Prompt.new(active_color: :cyan)
      setup_logger(app_config.log_file_path)
      attempt_auto_login(app_config)
    end

    # user management commands

    desc "register", "register a new user account"
    def register
      username = @prompt.ask("Enter desired username:") do |q|
        q.required true
        q.validate(/\A[a-zA-Z0-9_]+\z/, "Username can only contain letters, numbers, and underscores.")
      end

      password = @prompt.mask("Enter password (min 6 characters):") do |q|
        q.required true
        q.validate ->(input) { input.length >= 6 }, "Password must be at least 6 characters."
      end

      password_confirm = @prompt.mask("Confirm password:") do |q|
        q.required true
      end

      unless password == password_confirm
        display_error("Passwords do not match. Please try again.")
        return
      end

      begin
        user = @user_service.register_user(username, password)
        display_success("User '#{user.username}' registered successfully!")
        @logger.info("User registered: #{user.username}")
        # Optionally, log the user in immediately after registration
        # login_user # or set @current_user = user and task_service.set_current_user_id
      rescue TaskManager::UsernameAlreadyExistsError => e
        display_error(e.message)
        @logger.warn("Registration failed (username exists): #{username}")
      rescue => e
        display_error("An unexpected error occurred during registration: #{e.message}")
        @logger.fatal("Registration failed: #{username} - #{e.message}")
      end
    end

    desc "login", "Log in to your account"
    def login
      if @current_user
        display_error("You are already logged in as '#{@current_user.username}'.")
        return
      end

      username = @prompt.ask("Enter your username:") do |q|
        q.required true
      end

      password = @prompt.mask("Enter your password:") do |q|
        q.required true
      end

      begin
        user = @user_service.authenticate_user(username, password)
        @current_user = user
        @task_service.set_current_user_id(user.id)
        TaskManager::Config::ApplicationConfig.instance.set_session_user_id(user.id)
        display_success("Logged in as '#{user.username}'!")
        # Display current user's tasks upon login
        list
      rescue TaskManager::UserNotFoundError, TaskManager::AuthenticationError => e
        display_error(e.message)
        @logger.warn("Login failed for '#{username}': #{e.message}")
      rescue => e
        display_error("An unexpected error occurred during login: #{e.message}")
        @logger.fatal("Login failed: #{username} - #{e.message}")
      end
    end

    desc "logout", "Log out of your account"
    def logout
      return display_error("Not logged in") unless @current_user
      
      username = @current_user.username
      @current_user = nil
      @task_service.set_current_user_id(nil)
      TaskManager::Config::ApplicationConfig.instance.clear_session
      display_success("Logged out successfully")
    end

    # --- Task Management Commands ---

    desc "add DESCRIPTION", "Add a new task"
    long_desc <<-LONGDESC
      `task_manager add "Buy groceries"` adds a new task.

      Options:
        --due-date, -d DATE  Set a due date (YYYY-MM-DD).
        --tags, -t TAG1,TAG2 Set comma-separated tags for the task.
        --priority, -p PRIORITY Set task priority (e.g., high, medium, low).
        --recurrence, -r RECURRENCE Set task recurrence (e.g., daily, weekly).
        --parent-task-id, -P ID Link to a parent task (for subtasks).
    LONGDESC
    option :due_date, aliases: :d, type: :string, desc: "Due date (YYYY-MM-DD)"
    option :tags, aliases: :t, type: :array, desc: "Comma-separated tags", banner: "TAG1,TAG2"
    option :priority, aliases: :p, type: :string, desc: "Priority (e.g., high, medium, low)"
    option :recurrence, aliases: :r, type: :string, desc: "Recurrence (e.g., daily, monthly)"
    option :parent_task_id, aliases: :P, type: :string, desc: "Parent task ID"
    def add(description)
      authenticate_user! # Ensure user is logged in
      begin
        task = @task_service.add_task(
          description: description,
          due_date: options[:due_date],
          tags: options[:tags],
          priority: options[:priority],
          recurrence: options[:recurrence],
          parent_task_id: options[:parent_task_id]
        )
        display_success("Task '#{task.description.colorize(:light_blue)}' added successfully with ID #{task.id}.")
        @logger.info("Task added by #{@current_user.username}: #{task.description} (ID: #{task.id})")
      rescue TaskManager::InvalidInputError => e
        display_error(e.message)
        @logger.error("Failed to add task for #{@current_user.username}: #{description} - #{e.message}")
      rescue => e
        display_error("An unexpected error occurred while adding task: #{e.message}")
        @logger.fatal("Failed to add task: #{description} - #{e.message}")
      end
    end

    desc "list", "list your tasks"
    long_desc <<-LONGDESC
      `task_manager list` lists all your tasks

      options:
        --completed, -c    show only completed tasks
        --pending, -p      show only pending tasks
        --overdue, -o      show only overdue tasks
        --tag, -t TAG      filter by specific tag
        --sort-by, -s FIELD sort by 'due_date', 'priority', or 'created_at'
    LONGDESC
    option :completed, aliases: :c, type: :boolean, default: false, desc: "show only completed tasks"
    option :pending, aliases: :p, type: :boolean, default: false, desc: "show only pending tasks"
    option :overdue, aliases: :o, type: :boolean, default: false, desc: "show only overdue tasks"
    option :tag, aliases: :t, type: :string, desc: "filter by tag"
    option :sort_by, aliases: :s, type: :string, enum: %w[due_date priority created_at], desc: "sort by field"
    def list
      authenticate_user!

      filter_options = {}
      
      # handle completion status
      if options[:completed]
          filter_options[:completed] = true
      elsif options[:pending]
          filter_options[:completed] = false
      end

      # apply filters
      filter_options[:tag] = options[:tag] if options[:tag]
      filter_options[:overdue] = options[:overdue] if options[:overdue]
      filter_options[:sort_by] = options[:sort_by] if options[:sort_by]

      begin
          tasks = @task_service.list_tasks(filter_options)
          tasks.empty? ? show_empty_task_message : display_tasks(tasks)
          @logger.info("tasks listed by #{@current_user.username} with filters: #{filter_options}")
      rescue => e
          display_error("failed to list tasks: #{e.message}")
          @logger.error("list failed: #{e.message}")
      end
    end

    desc "show ID", "Display details of a single task"
    def show(task_id)
      authenticate_user!
      begin
        task = @task_service.find_task_by_id(task_id)
        puts "\n--- Task Details ---".colorize(:light_blue)
        puts "ID: #{task.id}".colorize(:light_black)
        puts "Description: #{task.description.colorize(:cyan)}"
        puts "Status: #{task.completed ? 'Completed'.colorize(:green) : 'Pending'.colorize(:yellow)}"
        puts "Due Date: #{task.due_date ? task.due_date.strftime('%Y-%m-%d').colorize(:magenta) : 'N/A'} #{"(OVERDUE)".colorize(:red) if task.overdue?}"
        puts "Tags: #{task.tags.empty? ? 'None' : task.tags.join(', ').colorize(:light_magenta)}"
        puts "Priority: #{task.priority || 'N/A'}".colorize(:white)
        puts "Recurrence: #{task.recurrence || 'N/A'}".colorize(:light_white)
        puts "Parent Task ID: #{task.parent_task_id || 'N/A'}".colorize(:light_black)
        puts "Created At: #{task.created_at.strftime('%Y-%m-%d %H:%M:%S').colorize(:light_black)}"
        puts "Completed At: #{task.completed_at ? task.completed_at.strftime('%Y-%m-%d %H:%M:%S').colorize(:light_black) : 'N/A'}"
        puts "--------------------".colorize(:light_blue)
        @logger.info("Task shown by #{@current_user.username}: #{task_id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error(e.message)
        @logger.warn("Task not found for show command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("An unexpected error occurred while showing task: #{e.message}")
        @logger.fatal("Failed to show task: #{task_id} - #{e.message}")
      end
    end

    desc "complete ID", "Mark a task as completed"
    def complete(task_id)
      authenticate_user!
      begin
        task = @task_service.complete_task(task_id)
        display_success("Task '#{task.description.colorize(:light_blue)}' (ID: #{task.id}) marked as completed.")
        @logger.info("Task completed by #{@current_user.username}: #{task.id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error(e.message)
        @logger.warn("Task not found for complete command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("An unexpected error occurred while completing task: #{e.message}")
        @logger.fatal("Failed to complete task: #{task_id} - #{e.message}")
      end
    end

    desc "reopen ID", "Mark a task as incomplete"
    def reopen(task_id)
      authenticate_user!
      begin
        task = @task_service.reopen_task(task_id)
        display_success("Task '#{task.description.colorize(:light_blue)}' (ID: #{task.id}) marked as pending.")
        @logger.info("Task reopened by #{@current_user.username}: #{task.id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error(e.message)
        @logger.warn("Task not found for reopen command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("An unexpected error occurred while reopening task: #{e.message}")
        @logger.fatal("Failed to reopen task: #{task_id} - #{e.message}")
      end
    end

    desc "edit ID", "Edit an existing task"
    long_desc <<-LONGDESC
      `task_manager edit ID` Edits a task.

      Options:
        --description, -d DESCRIPTION New description for the task.
        --due-date, -D DATE         New due date (YYYY-MM-DD), use 'nil' to clear.
        --tags, -t TAG1,TAG2        New comma-separated tags, use 'none' to clear.
        --completed, -c             Mark as completed.
        --pending, -p               Mark as pending.
        --priority, -P PRIORITY     Set new priority (e.g., high, medium, low), use 'nil' to clear.
        --recurrence, -r RECURRENCE Set new recurrence (e.g., daily, monthly), use 'nil' to clear.
        --parent-task-id, -I ID     Set new parent task ID, use 'nil' to clear.
    LONGDESC
    option :description, aliases: :d, type: :string, desc: "New description"
    option :due_date, aliases: :D, type: :string, desc: "New due date (YYYY-MM-DD). Use 'nil' to clear."
    option :tags, aliases: :t, type: :array, desc: "New tags (comma-separated). Use 'none' to clear."
    option :completed, aliases: :c, type: :boolean, desc: "Mark as completed"
    option :pending, aliases: :p, type: :boolean, desc: "Mark as pending"
    option :priority, aliases: :P, type: :string, desc: "New priority. Use 'nil' to clear."
    option :recurrence, aliases: :r, type: :string, desc: "New recurrence. Use 'nil' to clear."
    option :parent_task_id, aliases: :I, type: :string, desc: "New parent task ID. Use 'nil' to clear."
    def edit(task_id)
      authenticate_user!
      updated_attributes = {}

      # map CLI options to Task model attributes, handling special values like 'nil' or 'none'
      updated_attributes[:description] = options[:description] if options.key?(:description)
      if options.key?(:due_date)
        updated_attributes[:due_date] = (options[:due_date].downcase == 'nil' ? nil : options[:due_date])
      end
      if options.key?(:tags)
        updated_attributes[:tags] = (options[:tags].map(&:downcase).include?('none') ? [] : options[:tags])
      end
      if options.key?(:priority)
        updated_attributes[:priority] = (options[:priority].downcase == 'nil' ? nil : options[:priority])
      end
      if options.key?(:recurrence)
        updated_attributes[:recurrence] = (options[:recurrence].downcase == 'nil' ? nil : options[:recurrence])
      end
      if options.key?(:parent_task_id)
        updated_attributes[:parent_task_id] = (options[:parent_task_id].downcase == 'nil' ? nil : options[:parent_task_id])
      end

      # handle completed/pending flags
      if options.key?(:completed)
        updated_attributes[:completed] = true
      elsif options.key?(:pending)
        updated_attributes[:completed] = false
      end

      if updated_attributes.empty?
        display_error("No attributes provided for update. Use --help for options.")
        return
      end

      begin
        task = @task_service.update_task(task_id, updated_attributes)
        display_success("Task '#{task.description.colorize(:light_blue)}' (ID: #{task.id}) updated successfully.")
        @logger.info("Task updated by #{@current_user.username}: #{task.id} with #{updated_attributes}")
      rescue TaskManager::TaskNotFoundError, TaskManager::InvalidInputError => e
        display_error(e.message)
        @logger.warn("Failed to edit task by #{@current_user.username}: #{task_id} - #{e.message}")
      rescue => e
        display_error("An unexpected error occurred while editing task: #{e.message}")
        @logger.fatal("Failed to edit task: #{task_id} - #{e.message}")
      end
    end

    desc "delete ID", "Delete a task"
    def delete(task_id)
      authenticate_user!
      if @prompt.yes?("Are you sure you want to delete task '#{task_id}'? This cannot be undone.".colorize(:red))
        begin
          @task_service.delete_task(task_id)
          display_success("Task ID #{task_id} deleted successfully.")
          @logger.info("Task deleted by #{@current_user.username}: #{task_id}")
        rescue TaskManager::TaskNotFoundError => e
          display_error(e.message)
          @logger.warn("Task not found for delete command by #{@current_user.username}: #{task_id}")
        rescue => e
          display_error("An unexpected error occurred while deleting task: #{e.message}")
          @logger.fatal("Failed to delete task: #{task_id} - #{e.message}")
        end
      else
        display_success("Deletion cancelled.")
      end
    end

    desc "export FORMAT FILENAME", "Export your tasks to a file (e.g., CSV)"
    long_desc <<-LONGDESC
      `task_manager export csv my_tasks.csv` Exports current user's tasks.

      FORMAT: Currently only 'csv' is supported.
      FILENAME: The path to the output file.
    LONGDESC
    def export(format, filename)
      authenticate_user!
      begin
        @task_service.export_tasks(format: format.to_sym, filename: filename)
        display_success("Tasks successfully exported to '#{filename}'!")
        @logger.info("Tasks exported by #{@current_user.username} to #{filename}")
      rescue TaskManager::InvalidInputError, TaskManager::FileError => e
        display_error(e.message)
        @logger.error("Failed to export tasks for #{@current_user.username}: #{e.message}")
      rescue => e
        display_error("An unexpected error occurred during export: #{e.message}")
        @logger.fatal("Failed to export tasks for #{@current_user.username}: #{e.message}")
      end
    end

    desc "import FORMAT FILENAME", "Import tasks from a file (e.g., CSV)"
    long_desc <<-LONGDESC
      `task_manager import csv my_tasks.csv` Imports tasks for the current user.
      Tasks will be added with new IDs and assigned to the current user.

      FORMAT: Currently only 'csv' is supported.
      FILENAME: The path to the input file.
    LONGDESC
    def import(format, filename)
      authenticate_user!
      begin
        @task_service.import_tasks(format: format.to_sym, filename: filename)
        display_success("Tasks successfully imported from '#{filename}'!")
        @logger.info("Tasks imported by #{@current_user.username} from #{filename}")
      rescue TaskManager::InvalidInputError, TaskManager::FileError => e
        display_error(e.message)
        @logger.error("Failed to import tasks for #{@current_user.username}: #{e.message}")
      rescue => e
        display_error("An unexpected error occurred during import: #{e.message}")
        @logger.fatal("Failed to import tasks for #{@current_user.username}: #{e.message}")
      end
    end

    # --- Help and Default Commands ---

    desc "whoami", "Display the currently logged in user"
    def whoami
      if @current_user
        puts "You are currently logged in as: #{@current_user.username.colorize(:cyan)}"
      else
        puts "You are not logged in. Use `task_manager login` or `task_manager register`."
      end
    end

    # Default command when no subcommand is given (e.g., just `task_manager`)
    # Can be configured to show help or list tasks if logged in.
    def self.exit_on_failure?
      true # Exit with non-zero status code on error
    end

    # --- Private Helper Methods ---
    no_commands do # Methods within this block will not be exposed as Thor commands
      def setup_logger(log_path)
        @logger = Logger.new(log_path)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
        end
      end

      def attempt_auto_login(config)
        if (session_user_id = config.get_session_user_id)
          if (user = @user_service.find_user_by_id(session_user_id))
            @current_user = user
            @task_service.set_current_user_id(user.id)
          else
            config.clear_session
          end
        end
      end

      def display_tasks(tasks)
        if tasks.empty?
          puts "\nNo tasks found for you."
          return
        end

        puts "\n--- Your Tasks (#{@current_user.username}) ---".colorize(:blue)
        tasks.each_with_index do |task, index|
          status_icon = task.completed ? "✓".colorize(:green) : "✗".colorize(:yellow)
          due_date_display = task.due_date ? task.due_date.strftime('%Y-%m-%d') : 'N/A'
          due_date_color = :white
          if task.overdue? && !task.completed
            due_date_color = :red
          elsif task.due_date && task.due_date <= Date.today + 7 # Due within next 7 days
            due_date_color = :light_red
          end

          tags_display = task.tags.empty? ? "" : " " + "[#{task.tags.join(', ').colorize(:light_magenta)}]"
          priority_display = task.priority ? " (#{task.priority.upcase.colorize(:magenta)})" : ""

          # Truncate description for display
          description_display = task.description
          if description_display.length > 50
            description_display = description_display[0..47] + "..."
          end

          puts "#{status_icon} #{index + 1}. #{description_display.colorize(:cyan)} #{priority_display} #{tags_display} (Due: #{due_date_display.colorize(due_date_color)}) ID: #{task.id.colorize(:light_black)}"
        end
        puts "------------------------------------".colorize(:blue)
      end

      def display_error(message)
        puts "ERROR: #{message}".colorize(:red)
      end

      def display_success(message)
        puts "SUCCESS: #{message}".colorize(:green)
      end

      def authenticate_user!
        unless @current_user
          raise Thor::Error, "You must be logged in to perform this action. Please use `task_manager login` or `task_manager register`."
        end
      end
    end
  end
end