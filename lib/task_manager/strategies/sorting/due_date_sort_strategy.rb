require_relative 'base_sort_strategy'

module TaskManager
  module Strategies
    module Sorting
      # sorts tasks primarily by due date, with nil due dates coming last,
      # and completed tasks appearing after incomplete ones
      class DueDateSortStrategy < BaseSortStrategy
        # sorts tasks by their due date
        # leverages the comparison logic defined in the Task model's `<=>` operator
        # @param tasks [Array<TaskManager::Models::Task>] the array of tasks to sort
        # @return [Array<TaskManager::Models::Task>] the sorted array of tasks
        def sort(tasks)
          # the Task model's <=> operator handles nil due dates
          # and prioritizes incomplete/overdue tasks
          tasks.sort
        end
      end
    end
  end
end