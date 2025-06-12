require 'date'
require 'time'
require 'active_record'
require 'json'
require_relative '../persistence/database_store'
require 'securerandom'
require_relative '../config/application_config'

module TaskManager
  module Models
    class Task < ActiveRecord::Base
      # Establish database connection
      establish_connection(
        adapter: 'sqlite3',
        database: File.join(TaskManager::Config::ApplicationConfig.instance.data_directory, 'task_manager.db')
      )

      self.table_name = 'tasks'
      self.primary_key = 'id'

      # Define attributes using ActiveRecord's attribute API
      attribute :title, :string
      attribute :user_id, :string
      attribute :description, :text
      attribute :status, :string, default: 'pending'
      attribute :due_date, :date
      attribute :tags, :json, default: []
      attribute :completed_at, :datetime
      attribute :priority, :string
      attribute :recurrence, :json, default: {}
      attribute :parent_task_id, :string
      attribute :completed, :boolean, default: false

      # Validations
      validates :title, presence: true
      validates :user_id, presence: true
      validates :description, presence: true
      validates :status, presence: true, inclusion: { in: %w[pending completed] }

      # Callbacks
      before_create :ensure_id
      before_save :normalize_tags
      before_save :set_created_at_if_missing
      before_save :sync_status_and_completed

      # Scopes
      scope :completed, -> { where(status: 'completed') }
      scope :incomplete, -> { where.not(status: 'completed') }
      scope :overdue, -> { where('due_date < ? AND status != ?', Date.today, 'completed') }
      scope :for_user, ->(user_id) { where(user_id: user_id) }
      scope :with_tag, ->(tag) { where('tags LIKE ?', "%\"#{tag.downcase}\"%") }

      # creates a task instance from a hash
      # @param hash [Hash] task data
      # @return [Task] new task instance
      def self.from_h(attributes)
        new(
          id: attributes['id'],
          user_id: attributes['user_id'],
          title: attributes['title'],
          description: attributes['description'],
          status: attributes['status'] || 'pending',
          due_date: attributes['due_date'] ? Time.parse(attributes['due_date']) : nil,
          tags: attributes['tags'] || [],
          completed_at: attributes['completed_at'] ? Time.parse(attributes['completed_at']) : nil,
          priority: attributes['priority'],
          recurrence: attributes['recurrence'],
          parent_task_id: attributes['parent_task_id']
        )
      end

      # handles comma-separated tags input
      def tags=(new_tags)
        super(Array(new_tags).flat_map { |tag| tag.to_s.split(',').map(&:strip) }.reject(&:empty?).uniq)
      end

      # marks task as complete
      def complete!
        update!(status: 'completed', completed_at: Time.current, completed: true)
      end

      # reopens a completed task
      def reopen!
        update!(status: 'pending', completed_at: nil, completed: false)
      end

      # checks if task is past due date
      # @return [Boolean] true if task is overdue
      def overdue?
        return false if status == 'completed'

        due_date && due_date < Date.today
      end

      # checks if task has specific tag
      # @param tag_name [String] tag to check
      # @return [Boolean] true if tag exists
      def has_tag?(tag)
        tags.include?(tag.downcase)
      end

      # updates task attributes
      # @param attributes [Hash] new attribute values
      def update(attributes)
        attributes.each do |key, value|
          send("#{key}=", value)
        end
        self.completed_at = Time.now if attributes[:status] == 'completed' && status_changed?
        save
      end

      # converts task to hash for storage
      # @return [Hash] task data
      def to_h
        {
          'id' => id,
          'user_id' => user_id,
          'title' => title,
          'description' => description,
          'status' => status,
          'due_date' => due_date&.iso8601,
          'tags' => tags,
          'completed_at' => completed_at&.iso8601,
          'priority' => priority,
          'recurrence' => recurrence,
          'parent_task_id' => parent_task_id,
          'created_at' => created_at&.iso8601,
          'updated_at' => self.class.column_names.include?('updated_at') ? updated_at&.iso8601 : nil
        }.compact
      end

      include Comparable

      # compares tasks for sorting
      # sort order: completion status, overdue status, due date (grouped), priority (within due date groups), creation date
      def <=>(other)
        return 0 unless other.is_a?(Task)

        # First compare by completion status (incomplete tasks first)
        status_comparison = (status == 'completed' ? 1 : 0) <=> (other.status == 'completed' ? 1 : 0)
        return status_comparison unless status_comparison.zero?

        # Then compare by overdue status (non-overdue tasks first for incomplete tasks)
        overdue_comparison = (overdue? ? 1 : 0) <=> (other.overdue? ? 1 : 0)
        return overdue_comparison unless overdue_comparison.zero?

        # Then compare by due date (earlier dates first)
        if due_date && other.due_date
          due_date_comparison = due_date <=> other.due_date
          return due_date_comparison unless due_date_comparison.zero?
        elsif other.due_date
          return 1 # tasks without due dates come after tasks with due dates
        elsif due_date
          return -1 # tasks with due dates come before tasks without due dates
        end

        # If due dates are the same (or both nil), compare by priority (high priority first)
        priority_order = { 'high' => 0, 'medium' => 1, 'low' => 2, nil => 3 }
        priority_comparison = (priority_order[priority] || 3) <=> (priority_order[other.priority] || 3)
        return priority_comparison unless priority_comparison.zero?

        # If all else is equal, compare by creation date (older first for stable sorting)
        created_at <=> other.created_at
      end

      private

      def ensure_id
        self.id ||= SecureRandom.uuid
      end

      def normalize_tags
        self.tags = tags.map(&:downcase).uniq if tags.present?
      end

      def set_created_at_if_missing
        self.created_at ||= Time.current
      end

      def sync_status_and_completed
        self.completed = (status == 'completed')
        self.completed_at = Time.current if status == 'completed' && status_changed?
      end
    end
  end
end
