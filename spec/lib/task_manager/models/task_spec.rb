require 'spec_helper'
require_relative '../../../../lib/task_manager/models/task'

RSpec.describe TaskManager::Models::Task do
  let(:user_id) { 'test-user-123' }
  let(:title) { 'Test Task' }
  let(:description) { 'This is a test task' }
  let(:due_date) { Date.today + 7 }
  let(:tags) { ['test', 'important'] }
  let(:priority) { 'high' }
  let(:recurrence) { { 'frequency' => 'daily', 'interval' => 1 } }

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    described_class.delete_all
  end

  describe 'validations' do
    it 'requires a title' do
      task = described_class.new(
        user_id: user_id,
        description: description
      )
      expect(task).not_to be_valid
      expect(task.errors[:title]).to include("can't be blank")
    end

    it 'requires a user_id' do
      task = described_class.new(
        title: title,
        description: description
      )
      expect(task).not_to be_valid
      expect(task.errors[:user_id]).to include("can't be blank")
    end

    it 'requires a description' do
      task = described_class.new(
        title: title,
        user_id: user_id
      )
      expect(task).not_to be_valid
      expect(task.errors[:description]).to include("can't be blank")
    end
  end

  describe 'callbacks' do
    it 'generates a UUID if id is not provided' do
      task = described_class.new(
        title: title,
        user_id: user_id,
        description: description
      )
      task.save!
      expect(task.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'sets created_at if not provided' do
      task = described_class.new(
        title: title,
        user_id: user_id,
        description: description
      )
      task.save!
      expect(task.created_at).not_to be_nil
    end

    it 'normalizes tags' do
      task = described_class.new(
        title: title,
        user_id: user_id,
        description: description,
        tags: ['tag1, tag2', 'tag3', 'tag1']
      )
      task.save!
      expect(task.tags).to match_array(['tag1', 'tag2', 'tag3'])
    end
  end

  describe 'scopes' do
    before do
      # Create some test tasks
      described_class.create!(
        title: 'Completed Task',
        user_id: user_id,
        description: 'A completed task',
        status: 'completed',
        completed_at: Time.now
      )
      described_class.create!(
        title: 'Pending Task',
        user_id: user_id,
        description: 'A pending task',
        status: 'pending'
      )
      described_class.create!(
        title: 'Overdue Task',
        user_id: user_id,
        description: 'An overdue task',
        due_date: Date.today - 1,
        status: 'pending'
      )
    end

    it 'filters completed tasks' do
      expect(described_class.completed.count).to eq(1)
    end

    it 'filters incomplete tasks' do
      expect(described_class.incomplete.count).to eq(2)
    end

    it 'filters overdue tasks' do
      expect(described_class.overdue.count).to eq(1)
    end

    it 'filters tasks by user' do
      expect(described_class.for_user(user_id).count).to eq(3)
    end

    it 'filters tasks by tag' do
      task = described_class.create!(
        title: 'Tagged Task',
        user_id: user_id,
        description: 'A task with tags',
        tags: ['important']
      )
      expect(described_class.with_tag('important').count).to eq(1)
    end
  end

  describe '#complete!' do
    let(:task) do
      described_class.create!(
        title: title,
        user_id: user_id,
        description: description
      )
    end

    it 'marks task as completed' do
      task.complete!
      expect(task.status).to eq('completed')
      expect(task.completed_at).not_to be_nil
    end
  end

  describe '#reopen!' do
    let(:task) do
      described_class.create!(
        title: title,
        user_id: user_id,
        description: description,
        status: 'completed',
        completed_at: Time.now
      )
    end

    it 'marks task as pending' do
      task.reopen!
      expect(task.status).to eq('pending')
      expect(task.completed_at).to be_nil
    end
  end

  describe '#overdue?' do
    it 'returns true for overdue incomplete tasks' do
      task = described_class.create!(
        title: title,
        user_id: user_id,
        description: description,
        due_date: Date.today - 1
      )
      expect(task.overdue?).to be true
    end

    it 'returns false for completed tasks' do
      task = described_class.create!(
        title: title,
        user_id: user_id,
        description: description,
        due_date: Date.today - 1,
        status: 'completed'
      )
      expect(task.overdue?).to be false
    end
  end

  describe '#has_tag?' do
    let(:task) do
      described_class.create!(
        title: title,
        user_id: user_id,
        description: description,
        tags: ['test', 'important']
      )
    end

    it 'returns true for existing tag' do
      expect(task.has_tag?('test')).to be true
    end

    it 'returns false for non-existing tag' do
      expect(task.has_tag?('nonexistent')).to be false
    end

    it 'is case insensitive' do
      expect(task.has_tag?('TEST')).to be true
    end
  end

  describe '#to_h' do
    let(:task) do
      described_class.create!(
        title: title,
        user_id: user_id,
        description: description,
        due_date: due_date,
        tags: tags,
        priority: priority,
        recurrence: recurrence
      )
    end

    it 'converts task to hash with all attributes' do
      hash = task.to_h
      expect(hash['id']).to eq(task.id)
      expect(hash['title']).to eq(title)
      expect(hash['description']).to eq(description)
      expect(hash['status']).to eq(task.status)
      expect(hash['priority']).to eq(priority)
      expect(hash['due_date']).to eq(due_date.iso8601)
      expect(hash['created_at']).to eq(task.created_at.iso8601)
      expect(hash['completed_at']).to be_nil
      expect(hash['tags']).to eq(tags)
      expect(hash['user_id']).to eq(user_id)
    end
  end

  describe '.from_h' do
    let(:task_hash) do
      {
        'title' => title,
        'user_id' => user_id,
        'description' => description,
        'due_date' => due_date.iso8601,
        'tags' => tags,
        'priority' => priority,
        'recurrence' => recurrence
      }
    end

    it 'creates task instance from hash' do
      task = described_class.from_h(task_hash)
      task.save!
      expect(task.title).to eq(title)
      expect(task.user_id).to eq(user_id)
      expect(task.description).to eq(description)
      expect(task.due_date).to eq(due_date)
      expect(task.tags).to eq(tags)
      expect(task.priority).to eq(priority)
      expect(task.recurrence).to eq(recurrence)
    end

    it 'handles missing optional attributes' do
      task_hash.delete('tags')
      task_hash.delete('priority')
      task_hash.delete('recurrence')
      task = described_class.from_h(task_hash)
      task.save!
      expect(task.tags).to eq([])
      expect(task.priority).to be_nil
      expect(task.recurrence).to be_nil
    end
  end

  describe 'Comparable' do
    let(:task1) do
      described_class.create!(
        title: 'Task 1',
        user_id: user_id,
        description: 'First task',
        due_date: Date.today + 1,
        priority: 'high'
      )
    end

    let(:task2) do
      described_class.create!(
        title: 'Task 2',
        user_id: user_id,
        description: 'Second task',
        due_date: Date.today + 2,
        priority: 'medium'
      )
    end

    let(:task3) do
      described_class.create!(
        title: 'Task 3',
        user_id: user_id,
        description: 'Third task',
        due_date: Date.today + 1,
        priority: 'low'
      )
    end

    it 'sorts by completion status' do
      task2.complete!
      expect([task1, task2, task3].sort).to eq([task1, task3, task2])
    end

    it 'sorts by overdue status' do
      task1.update(due_date: Date.today - 1)
      expect([task1, task2, task3].sort).to eq([task3, task2, task1])
    end

    it 'sorts by due date' do
      expect([task1, task2, task3].sort).to eq([task1, task3, task2])
    end

    it 'sorts by priority' do
      expect([task1, task2, task3].sort).to eq([task1, task3, task2])
    end
  end
end
