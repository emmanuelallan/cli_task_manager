require 'observer'

module TaskManager
  module Notifications
    # notifies observers of task events
    class Notifier
      include Observable

      # sets up notification handler
      def initialize
        # No initialization needed for Observable
      end

      # broadcasts task events to observers
      # @param observable_task [Task] task that changed
      # @param event_type [Symbol] event type (:task_completed, :task_overdue, :task_created, etc.)
      def update(observable_task, event_type)
        @logger ||= Logger.new($stdout)
        @logger.info("Notifier: Task '#{observable_task.title}' triggered event '#{event_type}'.")

        changed
        notify_observers(observable_task, event_type)
      end
    end
  end
end
