require_relative 'base_sort_strategy'

module TaskManager
  module Strategies
    module Sorting
      # sorts tasks by priority (high > medium > low)
      class PrioritySortStrategy < BaseSortStrategy
        # priority level mapping for sorting
        PRIORITY_MAP = {
          'high' => 3,
          'medium' => 2,
          'low' => 1,
          nil => 0
        }.freeze

        # sorts tasks by priority, completion status and date
        # @param tasks [Array<Task>] tasks to sort
        # @return [Array<Task>] sorted tasks
        def sort(tasks)
          tasks.sort do |a, b|
            # sort by completion first
            comp_status = compare_completion_status(a, b)
            next comp_status unless comp_status.zero?

            # then by priority
            comp_priority = compare_priority(a, b)
            next comp_priority unless comp_priority.zero?

            # finally by creation date
            a.created_at <=> b.created_at
          end
        end

        private

        # compares task completion status
        # @return [Integer] comparison result (-1, 0, 1)
        def compare_completion_status(a, b)
          a.completed == b.completed ? 0 : (a.completed ? 1 : -1)
        end

        # compares task priorities using priority map
        # @return [Integer] comparison result (-1, 0, 1)
        def compare_priority(a, b)
          PRIORITY_MAP.fetch(b.priority, 0) <=> PRIORITY_MAP.fetch(a.priority, 0)
        end
      end
    end
  end
end