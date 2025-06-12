require_relative 'base_sort_strategy'

module TaskManager
  module Strategies
    module Sorting
      # Sorts tasks primarily by due date, with nil due dates coming last,
      # and completed tasks usually appearing after incomplete ones.
      class DueDateSortStrategy < BaseSortStrategy
        # Sorts tasks by their due date.
        # This implementation leverages the comparison logic defined in the Task model's `<=>` operator,
        # but you could implement custom logic here if needed.
        # @param tasks [Array<TaskManager::Models::Task>] The array of tasks to sort.
        # @return [Array<TaskManager::Models::Task>] The sorted array of tasks.
        def sort(tasks)
          # The Task model's <=> operator is ideal for this, as it handles nil due dates
          # and typically prioritizes incomplete/overdue tasks.
          tasks.sort
        end
      end
    end
  end
end