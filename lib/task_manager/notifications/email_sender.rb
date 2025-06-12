module TaskManager
  module Notifications
    # handles email notifications for task events
    class EmailSender
      # email service client for sending notifications
      attr_reader :email_service

      # sets up email sender with service client
      # @param email_service [Object] email service instance
      def initialize(email_service)
        @email_service = email_service
        puts "EmailSender initialized and ready to observe."
      end

      # handles task event notifications
      # @param observable_task [Task] task that triggered event
      # @param event_type [Symbol] type of event that occurred
      def update(observable_task, event_type)
        case event_type
        when :task_completed
          send_task_completed_email(observable_task)
        when :task_overdue_check
          send_task_overdue_email(observable_task) unless observable_task.completed
        else
          puts "EmailSender: Received unhandled event_type: #{event_type} for task '#{observable_task.description}'"
        end
      end

      private

      # sends completion notification
      # @param task [Task] completed task
      def send_task_completed_email(task)
        puts "--- Simulating Email Send ---".colorize(:light_green)
        puts "TO: #{get_user_email(task.user_id)} (assuming user email lookup)"
        puts "SUBJECT: Task Completed: #{task.description}"
        puts "BODY: Great job! Your task '#{task.description}' (ID: #{task.id}) was marked as completed at #{task.completed_at}."
        puts "-----------------------------".colorize(:light_green)
        # @email_service.send_email(to: get_user_email(task.user_id), subject: "Task Completed", body: "...")
      end

      # sends overdue notification
      # @param task [Task] overdue task
      def send_task_overdue_email(task)
        puts "--- Simulating Email Send ---".colorize(:light_red)
        puts "TO: #{get_user_email(task.user_id)} (assuming user email lookup)"
        puts "SUBJECT: Urgent: Task Overdue! - #{task.description}"
        puts "BODY: Your task '#{task.description}' (ID: #{task.id}) was due on #{task.due_date.strftime('%Y-%m-%d')} and is now overdue!"
        puts "-----------------------------".colorize(:light_red)
      end

      # gets user email from id
      # @param user_id [String] user identifier
      # @return [String] email address
      def get_user_email(user_id)
        "user_#{user_id}@example.com"
      end
    end
  end
end