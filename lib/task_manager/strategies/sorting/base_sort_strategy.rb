module TaskManager
  module Strategies
    module Sorting
      # base class for sorting strategies
      class BaseSortStrategy
        # sorts a list of tasks
        # @param tasks [Array<Task>] tasks to sort
        # @return [Array<Task>] sorted tasks
        def sort(tasks)
          raise NotImplementedError, "#{self.class} must implement sort method"
        end
      end
    end
  end
end