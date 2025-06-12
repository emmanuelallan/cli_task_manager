require_relative 'base_filter_strategy'

module TaskManager
  module Strategies
    module Filtering
      # filters tasks by due date
      class DueDateFilterStrategy < BaseFilterStrategy
        # sets up date filter options
        # @param options [Hash] filter settings
        #   :before [Date] tasks due before date
        #   :after [Date] tasks due after date
        #   :on [Date] tasks due on exact date
        def initialize(options = {})
          @before_date = options[:before]
          @after_date = options[:after]
          @on_date = options[:on]
        end

        # applies date filters to task list
        # @param tasks [Array<Task>] tasks to filter
        # @return [Array<Task>] filtered tasks
        def filter(tasks)
          return tasks if no_filter_criteria?

          tasks.select do |task|
            next false unless task.due_date # skip tasks without dates

            matches_date_criteria?(task.due_date)
          end
        end

        private

        # checks if any date filters are set
        # @return [Boolean] true if no filters
        def no_filter_criteria?
          @before_date.nil? && @after_date.nil? && @on_date.nil?
        end

        # checks if date matches filter criteria
        # @param date [Date] date to check
        # @return [Boolean] true if date matches
        def matches_date_criteria?(date)
          return date == @on_date if @on_date
          return false if @before_date && date > @before_date
          return false if @after_date && date < @after_date

          true
        end
      end
    end
  end
end
