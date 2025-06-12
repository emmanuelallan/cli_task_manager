require 'rbconfig'
require 'logger'

module TaskManager
  module Notifications
    # handles system notifications for task events
    class SystemNotifier
      attr_reader :platform, :logger

      # sets up system notifier with platform detection
      def initialize
        @platform = detect_platform
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [SystemNotifier] #{msg}\n"
        end
      end

      # handles task event notifications
      # @param observable_task [Task] task that triggered event
      # @param event_type [Symbol] type of event that occurred
      def update(observable_task, event_type)
        case event_type
        when :task_completed
          send_task_completed_notification(observable_task)
        when :task_reopened
          send_task_reopened_notification(observable_task)
        when :task_created
          send_task_created_notification(observable_task)
        when :task_deleted
          send_task_deleted_notification(observable_task)
        when :task_overdue_check
          send_task_overdue_notification(observable_task) unless observable_task.completed
        when :task_due_soon
          send_task_due_soon_notification(observable_task) unless observable_task.completed
        else
          log_unknown_event(observable_task, event_type)
        end
      end

      private

      # sends completion notification
      # @param task [Task] completed task
      def send_task_completed_notification(task)
        completion_time = task.completed_at ? task.completed_at.strftime('%Y-%m-%d %H:%M') : 'now'
        send_notification(
          title: 'Task Completed',
          message: "Great job! Your task '#{task.title}' was completed at #{completion_time}.",
          urgency: 'normal'
        )
      end

      # sends task reopened notification
      # @param task [Task] reopened task
      def send_task_reopened_notification(task)
        send_notification(
          title: 'Task Reopened',
          message: "Task '#{task.title}' has been marked as pending again.",
          urgency: 'normal'
        )
      end

      # sends task created notification
      # @param task [Task] created task
      def send_task_created_notification(task)
        send_notification(
          title: 'Task Created',
          message: "New task '#{task.title}' has been created.",
          urgency: 'low'
        )
      end

      # sends task deleted notification
      # @param task [Task] deleted task
      def send_task_deleted_notification(task)
        send_notification(
          title: 'Task Deleted',
          message: "Task '#{task.title}' has been deleted.",
          urgency: 'normal'
        )
      end

      # sends overdue notification
      # @param task [Task] overdue task
      def send_task_overdue_notification(task)
        send_notification(
          title: 'Task Overdue!',
          message: "Your task '#{task.title}' was due on #{task.due_date.strftime('%Y-%m-%d')} and is now overdue!",
          urgency: 'critical'
        )
      end

      # sends due soon notification
      # @param task [Task] task due soon
      def send_task_due_soon_notification(task)
        send_notification(
          title: 'Task Due Soon',
          message: "Your task '#{task.title}' is due on #{task.due_date.strftime('%Y-%m-%d')}.",
          urgency: 'normal'
        )
      end

      # sends notification based on platform
      # @param title [String] notification title
      # @param message [String] notification message
      # @param urgency [String] notification urgency (low, normal, critical)
      def send_notification(title:, message:, urgency: 'normal')
        begin
          case @platform
          when 'macos'
            send_macos_notification(title: title, message: message, urgency: urgency)
          when 'linux'
            send_linux_notification(title: title, message: message, urgency: urgency)
          when 'windows'
            send_windows_notification(title: title, message: message, urgency: urgency)
          else
            send_console_notification(title: title, message: message, urgency: urgency)
          end
        rescue => e
          log_error(e)
          # Fallback to console notification
          send_console_notification(title: title, message: message, urgency: urgency)
        end
      end

      # sends macOS notification using terminal-notifier
      # @param title [String] notification title
      # @param message [String] notification message
      # @param urgency [String] notification urgency
      def send_macos_notification(title:, message:, urgency:)
        require 'terminal-notifier'
        
        TerminalNotifier.notify(
          message,
          title: title,
          sound: urgency == 'critical' ? 'Basso' : 'default'
        )
        
        @logger.info("macOS notification sent: #{title}")
      end

      # sends Linux notification using libnotify
      # @param title [String] notification title
      # @param message [String] notification message
      # @param urgency [String] notification urgency
      def send_linux_notification(title:, message:, urgency:)
        require 'libnotify'
        
        Libnotify.show(
          summary: title,
          body: message,
          urgency: map_urgency(urgency),
          timeout: urgency == 'critical' ? 0 : 5000
        )
        
        @logger.info("Linux notification sent: #{title}")
      end

      # sends Windows notification using PowerShell
      # @param title [String] notification title
      # @param message [String] notification message
      # @param urgency [String] notification urgency
      def send_windows_notification(title:, message:, urgency:)
        # Use PowerShell to send Windows toast notification
        script = <<~POWERSHELL
          [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
          [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
          [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

          $template = @"
          <toast>
              <visual>
                  <binding template="ToastGeneric">
                      <text>#{title}</text>
                      <text>#{message}</text>
                  </binding>
              </visual>
          </toast>
          "@

          $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
          $xml.LoadXml($template)
          $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
          [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("TaskManager").Show($toast)
        POWERSHELL

        system("powershell", "-Command", script)
        @logger.info("Windows notification sent: #{title}")
      end

      # sends console notification as fallback
      # @param title [String] notification title
      # @param message [String] notification message
      # @param urgency [String] notification urgency
      def send_console_notification(title:, message:, urgency:)
        urgency_color = case urgency
                        when 'critical' then :red
                        when 'normal' then :yellow
                        else :green
                        end

        puts "\n--- System Notification ---".colorize(urgency_color)
        puts "Title: #{title}".colorize(:white)
        puts "Message: #{message}".colorize(:white)
        puts "Urgency: #{urgency.upcase}".colorize(urgency_color)
        puts "Platform: #{@platform}".colorize(:light_black)
        puts "------------------------".colorize(urgency_color)
        
        @logger.info("Console notification sent: #{title}")
      end

      # detects the current platform
      # @return [String] platform name (macos, linux, windows, unknown)
      def detect_platform
        host_os = RbConfig::CONFIG['host_os']
        
        case host_os
        when /darwin/i
          'macos'
        when /linux/i
          'linux'
        when /mswin|mingw|cygwin/i
          'windows'
        else
          'unknown'
        end
      end

      # maps urgency levels to platform-specific values
      # @param urgency [String] urgency level
      # @return [String] mapped urgency value
      def map_urgency(urgency)
        case urgency
        when 'critical'
          'critical'
        when 'normal'
          'normal'
        when 'low'
          'low'
        else
          'normal'
        end
      end

      # logs unknown event types
      # @param task [Task] task that triggered event
      # @param event_type [Symbol] unknown event type
      def log_unknown_event(task, event_type)
        @logger.warn("Unknown event type: #{event_type} for task '#{task.title}'")
      end

      # logs notification errors
      # @param error [StandardError] error that occurred
      def log_error(error)
        @logger.error("Notification failed: #{error.message}")
        @logger.debug("Error details: #{error.backtrace.join("\n")}")
      end
    end
  end
end 