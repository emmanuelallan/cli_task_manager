require_relative 'base_filter_strategy'

module TaskManager
  module Strategies
    module Filtering
      # filters tasks by tags
      class TagFilterStrategy < BaseFilterStrategy
        # sets up tag filter
        # @param tags [Array<String>, String] tag(s) to match
        def initialize(tags)
          @filter_tags = Array(tags).map(&:downcase)
        end

        # filters tasks by matching tags
        # @param tasks [Array<Task>] tasks to filter
        # @return [Array<Task>] filtered tasks
        def filter(tasks)
          return tasks if @filter_tags.empty?

          tasks.select do |task|
            @filter_tags.any? { |tag| task.has_tag?(tag) }
          end
        end
      end
    end
  end
end
