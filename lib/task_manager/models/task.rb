require 'date'
require 'time'

module TaskManager
    module Models
        class Task
            attr_reader :id, :user_id, :description, :created_at, :completed_at, :parent_task_id
            attr_accessor :due_date, :tags, :completed, :priority, :recurrence

            # creates a task instance from a hash
            # @param hash [Hash] task data
            # @return [Task] new task instance
            def self.from_h(hash)
                new(
                    id: hash['id'],
                    user_id: hash['user_id'],
                    description: hash['description'],
                    due_date: hash['due_date'] ? Date.parse(hash['due_date']) : nil,
                    tags: hash.fetch('tags', []),
                    completed: hash.fetch('completed', false),
                    created_at: Time.parse(hash['created_at']),
                    completed_at: hash['completed_at'] ? Time.parse(hash['completed_at']) : nil,
                    priority: hash['priority'],
                    recurrence: hash['recurrence'],
                    parent_task_id: hash['parent_task_id']
                )
            end

            # initialize a new task
            # @param id [String] unique identifier
            # @param user_id [String] owner of the task
            # @param description [String] task details
            def initialize(id:, user_id:, description:, due_date: nil, tags: [],
                     completed: false, created_at: Time.now, completed_at: nil,
                     priority: nil, recurrence: nil, parent_task_id: nil)
                @id = id
                @user_id = user_id
                @description = description
                @due_date = due_date.is_a?(String) ? Date.parse(due_date) : due_date
                @tags = Array(tags).flat_map { |tag| tag.to_s.split(',').map(&:strip) }
                @completed = completed
                @created_at = created_at
                @completed_at = completed_at
                @priority = priority
                @recurrence = recurrence
                @parent_task_id = parent_task_id
            end

            # handles comma-separated tags input
            def tags=(new_tags)
                @tags = Array(new_tags).flat_map { |tag| tag.to_s.split(',').map(&:strip) }
            end

            # marks task as complete
            def complete!
                @completed = true
                @completed_at = Time.now
            end

            # reopens a completed task
            def reopen!
                @completed = false
                @completed_at = nil
            end

            # checks if task is past due date
            # @return [Boolean] true if task is overdue
            def overdue?
                !@completed && @due_date && @due_date < Date.today
            end

            # checks if task has specific tag
            # @param tag_name [String] tag to check
            # @return [Boolean] true if tag exists
            def has_tag?(tag_name)
                @tags.map(&:downcase).include?(tag_name.downcase)
            end

            # updates task attributes
            # @param attributes [Hash] new attribute values
            def update(attributes)
                attributes.each do |key, value|
                    setter_method = "#{key}="
                    if respond_to?(setter_method)
                        case key.to_sym
                        when :due_date
                            self.due_date = value.is_a?(String) ? Date.parse(value) : value
                        when :tags
                            self.tags = Array(value)
                        else
                            send(setter_method, value)
                        end
                    end
                end

                if attributes.key?(:completed)
                    attributes[:completed] ? complete! : reopen!
                end
            end

            # converts task to hash for storage
            # @return [Hash] task data
            def to_h
                {
                'id' => @id,
                'user_id' => @user_id,
                'description' => @description,
                'due_date' => @due_date&.iso8601,
                'tags' => @tags,
                'completed' => @completed,
                'created_at' => @created_at.iso8601,
                'completed_at' => @completed_at&.iso8601,
                'priority' => @priority,
                'recurrence' => @recurrence,
                'parent_task_id' => @parent_task_id
                }
            end

            include Comparable

            # compares tasks for sorting
            # sort order: completion status, overdue status, due date, priority, creation date
            def <=> (other_task)
                completed_comparison = (completed ? 1 : 0) <=> (other_task.completed ? 1 : 0)
                return completed_comparison unless completed_comparison.zero?

                overdue_comparison = (other_task.overdue? ? 1 : 0) <=> (overdue? ? 1 : 0)
                return overdue_comparison unless overdue_comparison.zero?

                if @due_date && other_task.due_date
                    due_date_comparison = @due_date <=> other_task.due_date
                    return due_date_comparison unless due_date_comparison.zero?
                elsif other_task.due_date
                    return 1
                end

                priority_map = { 'high' => 3, 'medium' => 2, 'low' => 1, nil => 0 }
                p1 = priority_map.fetch(@priority, 0)
                p2 = priority_map.fetch(other_task.priority, 0)
                priority_comparison = p2 <=> p1
                return priority_comparison unless priority_comparison.zero?

                @created_at <=> other_task.created_at
            end
        end
    end
end