require 'spec_helper'
require_relative '../../../../lib/task_manager/services/task_service'
require_relative '../../../../lib/task_manager/models/task'

RSpec.describe TaskManager::Services::TaskService do
  let(:service) { described_class.new }
  let(:user_id) { 'test-user-123' }
  let(:task_attributes) do
    {
      title: 'Test Task',
      description: 'This is a test task',
      due_date: Date.today + 7,
      tags: %w[test important],
      priority: 'high'
    }
  end

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    TaskManager::Models::Task.delete_all
    service.set_current_user_id(user_id)
  end

  describe '#add_task' do
    it 'creates a new task with valid attributes' do
      task = service.add_task(task_attributes)
      expect(task).to be_a(TaskManager::Models::Task)
      expect(task.title).to eq(task_attributes[:title])
      expect(task.description).to eq(task_attributes[:description])
      expect(task.due_date).to eq(task_attributes[:due_date])
      expect(task.tags).to eq(task_attributes[:tags])
      expect(task.priority).to eq(task_attributes[:priority])
      expect(task.user_id).to eq(user_id)
    end

    it 'raises InvalidInputError for invalid task data' do
      expect do
        service.add_task({})
      end.to raise_error(TaskManager::InvalidInputError)
    end
  end

  describe '#find_task_by_id' do
    let!(:task) do
      service.add_task(task_attributes)
    end

    it 'returns task for existing id' do
      found_task = service.find_task_by_id(task.id)
      expect(found_task).to be_a(TaskManager::Models::Task)
      expect(found_task.id).to eq(task.id)
    end

    it 'raises TaskNotFoundError for non-existent id' do
      expect do
        service.find_task_by_id('nonexistent')
      end.to raise_error(TaskManager::TaskNotFoundError)
    end
  end

  describe '#list_tasks' do
    before do
      # Create some test tasks
      service.add_task(task_attributes.merge(title: 'Task 1', status: 'completed'))
      service.add_task(task_attributes.merge(title: 'Task 2', status: 'pending'))
      service.add_task(task_attributes.merge(
                         title: 'Task 3',
                         status: 'pending',
                         due_date: Date.today - 1
                       ))
    end

    it 'returns all tasks for current user' do
      tasks = service.list_tasks
      expect(tasks).to be_an(Array)
      expect(tasks.length).to eq(3)
    end

    it 'filters by status' do
      tasks = service.list_tasks(status: 'completed')
      expect(tasks.length).to eq(1)
      expect(tasks.first.title).to eq('Task 1')
    end

    it 'filters by tag' do
      tasks = service.list_tasks(tag: 'test')
      expect(tasks.length).to eq(3)
    end

    it 'filters overdue tasks' do
      tasks = service.list_tasks(overdue: true)
      expect(tasks.length).to eq(1)
      expect(tasks.first.title).to eq('Task 3')
    end

    it 'sorts by due date' do
      tasks = service.list_tasks(sort_by: 'due_date')
      expect(tasks.map(&:title)).to eq(['Task 3', 'Task 1', 'Task 2'])
    end

    it 'sorts by priority' do
      tasks = service.list_tasks(sort_by: 'priority')
      expect(tasks.map(&:priority).uniq).to eq(['high'])
    end

    it 'sorts by creation date' do
      tasks = service.list_tasks(sort_by: 'created_at')
      expect(tasks.length).to eq(3)
    end
  end

  describe '#update_task' do
    let!(:task) do
      service.add_task(task_attributes)
    end

    it 'updates task attributes' do
      updated_task = service.update_task(task.id, title: 'Updated Task')
      expect(updated_task.title).to eq('Updated Task')
    end

    it 'raises TaskNotFoundError for non-existent task' do
      expect do
        service.update_task('nonexistent', title: 'Updated Task')
      end.to raise_error(TaskManager::TaskNotFoundError)
    end

    it 'raises InvalidInputError for invalid update data' do
      expect do
        service.update_task(task.id, title: '')
      end.to raise_error(TaskManager::InvalidInputError)
    end
  end

  describe '#complete_task' do
    let!(:task) do
      service.add_task(task_attributes)
    end

    it 'marks task as completed' do
      completed_task = service.complete_task(task.id)
      expect(completed_task.status).to eq('completed')
      expect(completed_task.completed_at).not_to be_nil
    end

    it 'raises TaskNotFoundError for non-existent task' do
      expect do
        service.complete_task('nonexistent')
      end.to raise_error(TaskManager::TaskNotFoundError)
    end
  end

  describe '#reopen_task' do
    let!(:task) do
      service.add_task(task_attributes.merge(status: 'completed', completed_at: Time.now))
    end

    it 'marks task as pending' do
      reopened_task = service.reopen_task(task.id)
      expect(reopened_task.status).to eq('pending')
      expect(reopened_task.completed_at).to be_nil
    end

    it 'raises TaskNotFoundError for non-existent task' do
      expect do
        service.reopen_task('nonexistent')
      end.to raise_error(TaskManager::TaskNotFoundError)
    end
  end

  describe '#delete_task' do
    let!(:task) do
      service.add_task(task_attributes)
    end

    it 'deletes task' do
      service.delete_task(task.id)
      expect do
        service.find_task_by_id(task.id)
      end.to raise_error(TaskManager::TaskNotFoundError)
    end

    it 'raises TaskNotFoundError for non-existent task' do
      expect do
        service.delete_task('nonexistent')
      end.to raise_error(TaskManager::TaskNotFoundError)
    end
  end

  describe '#export_tasks' do
    before do
      service.add_task(task_attributes)
    end

    it 'exports tasks to CSV' do
      filename = 'test_export.csv'
      service.export_tasks(format: :csv, filename: filename)
      expect(File.exist?(filename)).to be true
      expect(File.read(filename)).to include('Test Task')
      File.delete(filename)
    end

    it 'raises InvalidInputError for unsupported format' do
      expect do
        service.export_tasks(format: :invalid, filename: 'test.txt')
      end.to raise_error(TaskManager::InvalidInputError)
    end
  end

  describe '#import_tasks' do
    let(:csv_content) do
      <<~CSV
        Title,Description,Status,Due Date,Tags,Priority,Created At,Completed At
        Imported Task,Test import,pending,2025-06-20,test;important,high,2025-06-12 10:00:00,
      CSV
    end

    before do
      File.write('test_import.csv', csv_content)
    end

    after do
      File.delete('test_import.csv')
    end

    it 'imports tasks from CSV' do
      service.import_tasks(format: :csv, filename: 'test_import.csv')
      tasks = service.list_tasks
      expect(tasks.length).to eq(1)
      expect(tasks.first.title).to eq('Imported Task')
    end

    it 'raises InvalidInputError for unsupported format' do
      expect do
        service.import_tasks(format: :invalid, filename: 'test.txt')
      end.to raise_error(TaskManager::InvalidInputError)
    end
  end
end
