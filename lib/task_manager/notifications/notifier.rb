require 'observer'

module TaskManager
  module Notifications
    # notifies observers of task events
    class Notifier
      include Observable

      # sets up notification handler
      def initialize
      end

      # broadcasts task events to observers
      # @param observable_task [Task] task that changed
      # @param event_type [Symbol] event type (:task_completed, :task_overdue)
      def update(observable_task, event_type)
        puts "Notifier: Task '#{observable_task.description}' triggered event '#{event_type}'."
        
        changed
        notify_observers(observable_task, event_type)
      end
    end
  end
end