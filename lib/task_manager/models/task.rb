require 'date'
require 'time'
require 'active_record'
require 'json'
require_relative '../persistence/database_store'

module TaskManager
    module Models
        class Task < ActiveRecord::Base
            # Ensure database connection is established
            TaskManager::Persistence::DatabaseStore.establish_connection

            self.table_name = 'tasks'
            self.primary_key = 'id'

            # Validations
            validates :title, presence: true
            validates :id, presence: true, uniqueness: true
            validates :user_id, presence: true
            validates :description, presence: true

            # Callbacks
            before_validation :ensure_id, on: :create
            before_validation :ensure_created_at, on: :create
            before_validation :normalize_tags

            # Serialize tags as JSON array
            serialize :tags, coder: JSON, type: Array
            serialize :recurrence, coder: JSON

            # Scopes
            scope :completed, -> { where(completed: true) }
            scope :incomplete, -> { where(completed: false) }
            scope :overdue, -> { where('due_date < ? AND completed = ?', Date.today, false) }
            scope :for_user, ->(user_id) { where(user_id: user_id) }
            scope :with_tag, ->(tag) { where("tags LIKE ?", "%#{tag}%") }

            attr_reader :id, :user_id, :description, :created_at, :completed_at, :parent_task_id
            attr_accessor :due_date, :tags, :completed, :priority, :recurrence

            # creates a task instance from a hash
            # @param hash [Hash] task data
            # @return [Task] new task instance
            def self.from_h(hash)
                new(
                    id: hash['id'],
                    title: hash['title'],
                    description: hash['description'],
                    status: hash['status'],
                    priority: hash['priority'],
                    due_date: hash['due_date'] ? Time.parse(hash['due_date']) : nil,
                    created_at: hash['created_at'] ? Time.parse(hash['created_at']) : nil,
                    completed_at: hash['completed_at'] ? Time.parse(hash['completed_at']) : nil,
                    tags: hash.fetch('tags', []),
                    user_id: hash['user_id']
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
                update(completed: true, completed_at: Time.now)
            end

            # reopens a completed task
            def reopen!
                update(completed: false, completed_at: nil)
            end

            # checks if task is past due date
            # @return [Boolean] true if task is overdue
            def overdue?
                !completed && due_date && due_date < Date.today
            end

            # checks if task has specific tag
            # @param tag_name [String] tag to check
            # @return [Boolean] true if tag exists
            def has_tag?(tag_name)
                tags.map(&:downcase).include?(tag_name.downcase)
            end

            # updates task attributes
            # @param attributes [Hash] new attribute values
            def update(attributes)
                attributes.each do |key, value|
                    send("#{key}=", value)
                end
                self.completed_at = Time.now if attributes[:completed] && completed_changed?
                save
            end

            # converts task to hash for storage
            # @return [Hash] task data
            def to_h
                {
                'id' => @id,
                'title' => title,
                'description' => @description,
                'status' => @completed,
                'priority' => @priority,
                'due_date' => @due_date&.iso8601,
                'created_at' => @created_at&.iso8601,
                'completed_at' => @completed_at&.iso8601,
                'tags' => @tags,
                'user_id' => @user_id
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
                elsif @due_date
                    return -1
                end

                priority_map = { 'high' => 3, 'medium' => 2, 'low' => 1, nil => 0 }
                p1 = priority_map.fetch(@priority, 0)
                p2 = priority_map.fetch(other_task.priority, 0)
                priority_comparison = p2 <=> p1
                return priority_comparison unless priority_comparison.zero?

                @created_at <=> other_task.created_at
            end

            private

            def ensure_id
                self.id ||= SecureRandom.uuid
            end

            def ensure_created_at
                self.created_at ||= Time.now
            end

            def normalize_tags
                return if @tags.nil?
                self.tags = @tags.reject(&:empty?).map(&:strip).uniq
            end
        end
    end
end