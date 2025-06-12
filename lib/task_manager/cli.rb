require 'thor'
require 'tty-prompt'
require 'tty-table'
require 'tty-box'
require 'tty-screen'
require 'colorize'
require 'logger'

require_relative 'services/user_service'
require_relative 'services/task_service'
require_relative 'models/task'
require_relative 'models/user'
require_relative 'core/errors'
require_relative 'config/application_config'
require_relative 'persistence/database_store'

module TaskManager
  # handles command line interface and user interactions
  class CLI < Thor
    attr_accessor :current_user

    # sets up cli with required services
    # @param args [Array] thor arguments
    def initialize(*args)
      super
      app_config = TaskManager::Config::ApplicationConfig.instance
      
      # Initialize database connection
      TaskManager::Persistence::DatabaseStore.establish_connection
      
      @user_service = Services::UserService.new
      @task_service = Services::TaskService.new
      @prompt = TTY::Prompt.new(active_color: :cyan)
      setup_logger(app_config.log_file_path)
      attempt_auto_login(app_config)
    end

    # user management commands

    desc "register", "register a new user account"
    def register
      display_header("📝 User Registration")
      
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
        display_error("❌ Passwords do not match. Please try again.")
        return
      end

      begin
        user = @user_service.register_user(username, password)
        display_success("✅ User '#{user.username}' registered successfully!")
        @logger.info("User registered: #{user.username}")
      rescue TaskManager::UsernameAlreadyExistsError => e
        display_error("❌ #{e.message}")
        @logger.warn("Registration failed (username exists): #{username}")
      rescue => e
        display_error("❌ An unexpected error occurred during registration: #{e.message}")
        @logger.fatal("Registration failed: #{username} - #{e.message}")
      end
    end

    desc "login", "Log in to your account"
    def login
      if @current_user
        display_warning("⚠️  You are already logged in as '#{@current_user.username}'.")
        return
      end

      display_header("🔐 User Login")

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
        display_success("✅ Logged in as '#{user.username}'!")
        
        # Check for overdue and due soon tasks after login
        check_task_notifications
        
        list
      rescue TaskManager::UserNotFoundError, TaskManager::AuthenticationError => e
        display_error("❌ #{e.message}")
        @logger.warn("Login failed for '#{username}': #{e.message}")
      rescue => e
        display_error("❌ An unexpected error occurred during login: #{e.message}")
        @logger.fatal("Login failed: #{username} - #{e.message}")
      end
    end

    desc "logout", "Log out of your account"
    def logout
      return display_error("❌ Not logged in") unless @current_user
      
      username = @current_user.username
      @current_user = nil
      @task_service.set_current_user_id(nil)
      TaskManager::Config::ApplicationConfig.instance.clear_session
      display_success("👋 Logged out successfully")
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
      authenticate_user!
      begin
        task = @task_service.add_task(
          title: description,
          description: description,
          due_date: options[:due_date],
          tags: options[:tags],
          priority: options[:priority],
          recurrence: options[:recurrence],
          parent_task_id: options[:parent_task_id]
        )
        display_success("✅ Task '#{task.title.colorize(:light_blue)}' added successfully with ID #{task.id}.")
        @logger.info("Task added by #{@current_user.username}: #{task.title} (ID: #{task.id})")
      rescue TaskManager::InvalidInputError => e
        display_error("❌ #{e.message}")
        @logger.error("Failed to add task for #{@current_user.username}: #{description} - #{e.message}")
      rescue => e
        display_error("❌ An unexpected error occurred while adding task: #{e.message}")
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
          filter_options[:status] = 'completed'
      elsif options[:pending]
          filter_options[:status] = 'pending'
      end

      # apply filters
      filter_options[:tag] = options[:tag] if options[:tag]
      filter_options[:overdue] = options[:overdue] if options[:overdue]
      filter_options[:sort_by] = options[:sort_by] if options[:sort_by]

      begin
          tasks = @task_service.list_tasks(filter_options)
          tasks.empty? ? show_empty_task_message : display_tasks_table(tasks)
          @logger.info("tasks listed by #{@current_user.username} with filters: #{filter_options}")
      rescue => e
          display_error("❌ failed to list tasks: #{e.message}")
          @logger.error("list failed: #{e.message}")
      end
    end

    desc "show ID", "Display details of a single task"
    def show(task_id)
      authenticate_user!
      begin
        task = @task_service.find_task_by_id(task_id)
        display_task_details(task)
        @logger.info("Task shown by #{@current_user.username}: #{task_id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error("❌ #{e.message}")
        @logger.warn("Task not found for show command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("❌ An unexpected error occurred while showing task: #{e.message}")
        @logger.fatal("Failed to show task: #{task_id} - #{e.message}")
      end
    end

    desc "complete ID", "Mark a task as completed"
    def complete(task_id)
      authenticate_user!
      begin
        task = @task_service.complete_task(task_id)
        display_success("✅ Task '#{task.title.colorize(:light_blue)}' (ID: #{task.id}) marked as completed.")
        @logger.info("Task completed by #{@current_user.username}: #{task.id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error("❌ #{e.message}")
        @logger.warn("Task not found for complete command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("❌ An unexpected error occurred while completing task: #{e.message}")
        @logger.fatal("Failed to complete task: #{task_id} - #{e.message}")
      end
    end

    desc "reopen ID", "Mark a task as incomplete"
    def reopen(task_id)
      authenticate_user!
      begin
        task = @task_service.reopen_task(task_id)
        display_success("🔄 Task '#{task.title.colorize(:light_blue)}' (ID: #{task.id}) marked as pending.")
        @logger.info("Task reopened by #{@current_user.username}: #{task.id}")
      rescue TaskManager::TaskNotFoundError => e
        display_error("❌ #{e.message}")
        @logger.warn("Task not found for reopen command by #{@current_user.username}: #{task_id}")
      rescue => e
        display_error("❌ An unexpected error occurred while reopening task: #{e.message}")
        @logger.fatal("Failed to reopen task: #{task_id} - #{e.message}")
      end
    end

    desc "edit ID", "Edit an existing task"
    long_desc <<-LONGDESC
      `task_manager edit ID` Edits a task.

      Options:
        --title, -t TITLE           New title for the task.
        --description, -d DESC      New description for the task.
        --due-date, -D DATE        New due date (YYYY-MM-DD), use 'nil' to clear.
        --tags, -T TAG1,TAG2       New comma-separated tags, use 'none' to clear.
        --completed, -c            Mark as completed.
        --pending, -p              Mark as pending.
        --priority, -P PRIORITY    Set new priority (e.g., high, medium, low), use 'nil' to clear.
        --recurrence, -r RECURRENCE Set new recurrence (e.g., daily, monthly), use 'nil' to clear.
        --parent-task-id, -I ID    Set new parent task ID, use 'nil' to clear.
    LONGDESC
    option :title, aliases: :t, type: :string, desc: "New title"
    option :description, aliases: :d, type: :string, desc: "New description"
    option :due_date, aliases: :D, type: :string, desc: "New due date (YYYY-MM-DD). Use 'nil' to clear."
    option :tags, aliases: :T, type: :array, desc: "New tags (comma-separated). Use 'none' to clear."
    option :completed, aliases: :c, type: :boolean, desc: "Mark as completed"
    option :pending, aliases: :p, type: :boolean, desc: "Mark as pending"
    option :priority, aliases: :P, type: :string, desc: "New priority. Use 'nil' to clear."
    option :recurrence, aliases: :r, type: :string, desc: "New recurrence. Use 'nil' to clear."
    option :parent_task_id, aliases: :I, type: :string, desc: "New parent task ID. Use 'nil' to clear."
    def edit(task_id)
      authenticate_user!
      updated_attributes = {}

      # map CLI options to Task model attributes, handling special values like 'nil' or 'none'
      updated_attributes[:title] = options[:title] if options.key?(:title)
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
        updated_attributes[:status] = 'completed'
      elsif options.key?(:pending)
        updated_attributes[:status] = 'pending'
      end

      if updated_attributes.empty?
        display_error("❌ No attributes provided for update. Use --help for options.")
        return
      end

      begin
        task = @task_service.update_task(task_id, updated_attributes)
        display_success("✏️  Task '#{task.title.colorize(:light_blue)}' (ID: #{task.id}) updated successfully.")
        @logger.info("Task updated by #{@current_user.username}: #{task.id} with #{updated_attributes}")
      rescue TaskManager::TaskNotFoundError, TaskManager::InvalidInputError => e
        display_error("❌ #{e.message}")
        @logger.warn("Failed to edit task by #{@current_user.username}: #{task_id} - #{e.message}")
      rescue => e
        display_error("❌ An unexpected error occurred while editing task: #{e.message}")
        @logger.fatal("Failed to edit task: #{task_id} - #{e.message}")
      end
    end

    desc "delete ID", "Delete a task"
    def delete(task_id)
      authenticate_user!
      if @prompt.yes?("🗑️  Are you sure you want to delete task '#{task_id}'? This cannot be undone.".colorize(:red))
        begin
          @task_service.delete_task(task_id)
          display_success("🗑️  Task ID #{task_id} deleted successfully.")
          @logger.info("Task deleted by #{@current_user.username}: #{task_id}")
        rescue TaskManager::TaskNotFoundError => e
          display_error("❌ #{e.message}")
          @logger.warn("Task not found for delete command by #{@current_user.username}: #{task_id}")
        rescue => e
          display_error("❌ An unexpected error occurred while deleting task: #{e.message}")
          @logger.fatal("Failed to delete task: #{task_id} - #{e.message}")
        end
      else
        display_info("🚫 Deletion cancelled.")
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
        display_success("📤 Tasks successfully exported to '#{filename}'!")
        @logger.info("Tasks exported by #{@current_user.username} to #{filename}")
      rescue TaskManager::InvalidInputError, TaskManager::FileError => e
        display_error("❌ #{e.message}")
        @logger.error("Failed to export tasks for #{@current_user.username}: #{e.message}")
      rescue => e
        display_error("❌ An unexpected error occurred during export: #{e.message}")
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
        display_success("📥 Tasks successfully imported from '#{filename}'!")
        @logger.info("Tasks imported by #{@current_user.username} from #{filename}")
      rescue TaskManager::InvalidInputError, TaskManager::FileError => e
        display_error("❌ #{e.message}")
        @logger.error("Failed to import tasks for #{@current_user.username}: #{e.message}")
      rescue => e
        display_error("❌ An unexpected error occurred during import: #{e.message}")
        @logger.fatal("Failed to import tasks for #{@current_user.username}: #{e.message}")
      end
    end

    desc "notifications", "Check for overdue and due soon tasks"
    def notifications
      authenticate_user!
      check_task_notifications
    end

    # --- Help and Default Commands ---

    desc "whoami", "Display the currently logged in user"
    def whoami
      if @current_user
        display_info("👤 You are currently logged in as: #{@current_user.username.colorize(:cyan)}")
      else
        display_warning("⚠️  You are not logged in. Use `task_manager login` or `task_manager register`.")
      end
    end

    # Default command when no subcommand is given (e.g., just `task_manager`)
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

      def check_task_notifications
        overdue_count = @task_service.check_overdue_tasks.count
        due_soon_count = @task_service.check_due_soon_tasks.count
        
        if overdue_count > 0 || due_soon_count > 0
          display_notification_box(overdue_count, due_soon_count)
        end
      end

      def display_tasks_table(tasks)
        if tasks.empty?
          show_empty_task_message
          return
        end

        # Prepare table data
        table_data = tasks.map.with_index do |task, index|
          [
            "#{index + 1}",
            get_status_icon(task.status),
            truncate_text(task.title, 40),
            get_priority_badge(task.priority),
            format_due_date(task),
            format_tags(task.tags),
            task.id[0..7] # Short ID
          ]
        end

        # Create table
        table = TTY::Table.new(
          header: ['#', 'Status', 'Title', 'Priority', 'Due Date', 'Tags', 'ID'],
          rows: table_data
        )

        # Display header
        display_header("📋 Your Tasks (#{@current_user.username})")
        
        # Render table with styling (fixed for TTY::Table >= 0.12)
        puts table.render(:unicode, padding: [0, 1], border: { separator: :each_row, style: :green })
      end

      def display_task_details(task)
        display_header("📄 Task Details")
        
        details = [
          ["ID", task.id],
          ["Title", task.title.colorize(:cyan)],
          ["Description", task.description.colorize(:cyan)],
          ["Status", get_status_badge(task.status)],
          ["Due Date", format_due_date_with_icon(task)],
          ["Tags", format_tags(task.tags)],
          ["Priority", get_priority_badge(task.priority)],
          ["Recurrence", task.recurrence || 'None'],
          ["Parent Task ID", task.parent_task_id || 'None'],
          ["Created At", task.created_at.strftime('%Y-%m-%d %H:%M:%S').colorize(:light_black)],
          ["Completed At", task.completed_at ? task.completed_at.strftime('%Y-%m-%d %H:%M:%S').colorize(:light_black) : 'N/A']
        ]

        table = TTY::Table.new(rows: details)
        puts table.render(:unicode, padding: [0, 1], border: :unicode) do |renderer|
          renderer.border.separator = :each_row
          renderer.border.style = :blue
        end
      end

      def display_header(title)
        puts TTY::Box.frame(
          title,
          padding: [0, 1],
          border: :thick,
          style: {
            border: { fg: :blue, bg: :black },
            title: { fg: :white, bg: :blue }
          }
        )
      end

      def display_notification_box(overdue_count, due_soon_count)
        content = [
          "🔔 Task Notifications",
          "",
          "⏰ Overdue tasks: #{overdue_count}".colorize(overdue_count > 0 ? :red : :green),
          "📅 Tasks due soon: #{due_soon_count}".colorize(due_soon_count > 0 ? :yellow : :green)
        ].join("\n")

        puts TTY::Box.frame(
          content,
          padding: [1, 2],
          border: :thick,
          style: {
            border: { fg: :yellow, bg: :black },
            title: { fg: :black, bg: :yellow }
          }
        )
      end

      def get_status_icon(status)
        case status
        when 'completed'
          "✅".colorize(:green)
        when 'pending'
          "⏳".colorize(:yellow)
        else
          "❓".colorize(:light_black)
        end
      end

      def get_status_badge(status)
        case status
        when 'completed'
          "✅ Completed".colorize(:green)
        when 'pending'
          "⏳ Pending".colorize(:yellow)
        else
          "❓ #{status.capitalize}".colorize(:light_black)
        end
      end

      def get_priority_badge(priority)
        return "⚪ None".colorize(:light_black) unless priority

        case priority.downcase
        when 'high'
          "🔴 HIGH".colorize(:red)
        when 'medium'
          "🟡 MEDIUM".colorize(:yellow)
        when 'low'
          "🟢 LOW".colorize(:green)
        else
          "⚪ #{priority.upcase}".colorize(:light_black)
        end
      end

      def format_due_date(task)
        return "📅 No due date".colorize(:light_black) unless task.due_date

        due_date_str = task.due_date.strftime('%Y-%m-%d')
        
        if task.overdue? && task.status != 'completed'
          "🚨 #{due_date_str} (OVERDUE)".colorize(:red)
        elsif task.due_date <= Date.today + 1
          "⚠️  #{due_date_str} (DUE SOON)".colorize(:yellow)
        else
          "📅 #{due_date_str}".colorize(:white)
        end
      end

      def format_due_date_with_icon(task)
        return "📅 No due date".colorize(:light_black) unless task.due_date

        due_date_str = task.due_date.strftime('%Y-%m-%d')
        
        if task.overdue? && task.status != 'completed'
          "🚨 #{due_date_str} (OVERDUE)".colorize(:red)
        elsif task.due_date <= Date.today + 1
          "⚠️  #{due_date_str} (DUE SOON)".colorize(:yellow)
        else
          "📅 #{due_date_str}".colorize(:white)
        end
      end

      def format_tags(tags)
        return "🏷️  No tags".colorize(:light_black) if tags.empty?

        "🏷️  #{tags.join(', ')}".colorize(:light_magenta)
      end

      def truncate_text(text, max_length)
        return text if text.length <= max_length
        "#{text[0..max_length-3]}...".colorize(:light_black)
      end

      def show_empty_task_message
        display_info("📭 No tasks found for you.")
      end

      def display_error(message)
        puts "❌ #{message}".colorize(:red)
      end

      def display_success(message)
        puts "✅ #{message}".colorize(:green)
      end

      def display_warning(message)
        puts "⚠️  #{message}".colorize(:yellow)
      end

      def display_info(message)
        puts "ℹ️  #{message}".colorize(:cyan)
      end

      def authenticate_user!
        unless @current_user
          raise Thor::Error, "❌ You must be logged in to perform this action. Please use `task_manager login` or `task_manager register`."
        end
      end
    end
  end
end