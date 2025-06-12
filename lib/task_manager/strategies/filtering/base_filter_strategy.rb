module TaskManager
  module Strategies
    module Filtering
      # base class for filtering task lists
      class BaseFilterStrategy
        # filters a list of tasks
        # @param tasks [Array<Task>] tasks to filter
        # @return [Array<Task>] filtered tasks
        def filter(tasks)
          raise NotImplementedError, "#{self.class} must implement filter method"
        end
      end
    end
  end
end
