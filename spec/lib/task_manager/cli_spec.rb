require 'spec_helper'
require_relative '../../../lib/task_manager/cli'
require_relative '../../../lib/task_manager/models/task'
require_relative '../../../lib/task_manager/models/user'

RSpec.describe TaskManager::CLI do
  let(:cli) { described_class.new }
  let(:username) { 'testuser' }
  let(:password) { 'password123' }
  let(:user_id) { 'test-user-123' }

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    TaskManager::Models::Task.delete_all
    TaskManager::Models::User.delete_all

    # Reset CLI state
    cli.current_user = nil
    cli.instance_variable_get(:@task_service).set_current_user_id(nil)

    # Mock the logger to avoid file I/O issues in tests
    logger = double('logger')
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(logger).to receive(:fatal)
    cli.instance_variable_set(:@logger, logger)
  end

  describe 'initialization' do
    it 'initializes with required services' do
      expect(cli.instance_variable_get(:@user_service)).to be_a(TaskManager::Services::UserService)
      expect(cli.instance_variable_get(:@task_service)).to be_a(TaskManager::Services::TaskService)
      expect(cli.instance_variable_get(:@prompt)).to be_a(TTY::Prompt)
      expect(cli.instance_variable_get(:@logger)).to be_a(RSpec::Mocks::Double)
    end
  end

  describe '#register' do
    before do
      allow(cli.instance_variable_get(:@prompt)).to receive(:ask).and_return(username)
      allow(cli.instance_variable_get(:@prompt)).to receive(:mask).and_return(password, password)
    end

    it 'registers a new user successfully' do
      expect { cli.register }.to change { TaskManager::Models::User.count }.by(1)
      expect(cli.instance_variable_get(:@logger)).to have_received(:info).with(/User registered: #{username}/)
    end

    it 'handles username already exists error' do
      # Register first user
      cli.register

      # Try to register same username again
      allow(cli.instance_variable_get(:@user_service)).to receive(:register_user).and_raise(
        TaskManager::UsernameAlreadyExistsError.new("Username '#{username}' already exists")
      )

      expect { cli.register }.not_to(change { TaskManager::Models::User.count })
      expect(cli.instance_variable_get(:@logger)).to have_received(:warn).with(/Registration failed \(username exists\)/)
    end

    it 'handles password mismatch' do
      allow(cli.instance_variable_get(:@prompt)).to receive(:mask).and_return(password, 'different_password')

      expect { cli.register }.not_to(change { TaskManager::Models::User.count })
    end
  end

  describe '#login' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    before do
      allow(cli.instance_variable_get(:@prompt)).to receive(:ask).and_return(username)
      allow(cli.instance_variable_get(:@prompt)).to receive(:mask).and_return(password)
    end

    it 'logs in successfully' do
      cli.login
      expect(cli.current_user).to eq(user)
      expect(cli.instance_variable_get(:@task_service).current_user_id).to eq(user_id)
    end

    it 'handles authentication error' do
      allow(cli.instance_variable_get(:@user_service)).to receive(:authenticate_user).and_raise(
        TaskManager::AuthenticationError.new('Invalid password')
      )

      cli.login
      expect(cli.current_user).to be_nil
      expect(cli.instance_variable_get(:@logger)).to have_received(:warn).with(/Login failed for '#{username}'/)
    end

    it 'prevents login when already logged in' do
      cli.current_user = user
      expect { cli.login }.not_to(change { cli.current_user })
    end
  end

  describe '#logout' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    it 'logs out successfully' do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)

      cli.logout
      expect(cli.current_user).to be_nil
      expect(cli.instance_variable_get(:@task_service).current_user_id).to be_nil
    end

    it 'handles logout when not logged in' do
      expect { cli.logout }.not_to raise_error
    end
  end

  describe '#add' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'adds a task successfully' do
      task_description = 'Buy groceries'
      expect { cli.add(task_description) }.to change { TaskManager::Models::Task.count }.by(1)

      task = TaskManager::Models::Task.last
      expect(task.title).to eq(task_description)
      expect(task.description).to eq(task_description)
      expect(task.user_id).to eq(user_id)
    end

    it 'adds a task with options' do
      task_description = 'Meeting with client'
      cli.options = {
        due_date: '2025-06-20',
        tags: %w[work important],
        priority: 'high',
        recurrence: 'weekly',
        parent_task_id: 'parent-123'
      }

      cli.add(task_description)

      task = TaskManager::Models::Task.last
      expect(task.title).to eq(task_description)
      expect(task.description).to eq(task_description)
      expect(task.due_date).to eq(Date.parse('2025-06-20'))
      expect(task.tags).to match_array(%w[work important])
      expect(task.priority).to eq('high')
      expect(task.recurrence).to eq('weekly')
      expect(task.parent_task_id).to eq('parent-123')
    end

    it 'handles invalid task data' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:add_task).and_raise(
        TaskManager::InvalidInputError.new('Title cannot be blank')
      )

      expect { cli.add('') }.not_to(change { TaskManager::Models::Task.count })
      expect(cli.instance_variable_get(:@logger)).to have_received(:error).with(/Failed to add task/)
    end
  end

  describe '#list' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task1) do
      TaskManager::Models::Task.create!(
        id: 'task-1',
        user_id: user_id,
        title: 'Task 1',
        description: 'First task',
        status: 'pending',
        due_date: Date.today + 1
      )
    end

    let!(:task2) do
      TaskManager::Models::Task.create!(
        id: 'task-2',
        user_id: user_id,
        title: 'Task 2',
        description: 'Second task',
        status: 'completed',
        due_date: Date.today - 1
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'lists all tasks' do
      expect { cli.list }.to output(/Task 1/).to_stdout
      expect { cli.list }.to output(/Task 2/).to_stdout
    end

    it 'filters by completed status' do
      cli.options = { completed: true }
      expect { cli.list }.to output(/Task 2/).to_stdout
      expect { cli.list }.not_to output(/Task 1/).to_stdout
    end

    it 'filters by pending status' do
      cli.options = { pending: true }
      expect { cli.list }.to output(/Task 1/).to_stdout
      expect { cli.list }.not_to output(/Task 2/).to_stdout
    end

    it 'filters by overdue status' do
      # Create an overdue task
      TaskManager::Models::Task.create!(
        id: 'task-3',
        user_id: user_id,
        title: 'Overdue Task',
        description: 'Overdue task',
        status: 'pending',
        due_date: Date.today - 1
      )

      cli.options = { overdue: true }
      expect { cli.list }.to output(/Overdue Task/).to_stdout
    end

    it 'filters by tag' do
      task1.update(tags: ['work'])
      cli.options = { tag: 'work' }
      expect { cli.list }.to output(/Task 1/).to_stdout
    end

    it 'sorts by due date' do
      cli.options = { sort_by: 'due_date' }
      expect { cli.list }.not_to raise_error
    end

    it 'sorts by priority' do
      cli.options = { sort_by: 'priority' }
      expect { cli.list }.not_to raise_error
    end

    it 'sorts by created_at' do
      cli.options = { sort_by: 'created_at' }
      expect { cli.list }.not_to raise_error
    end

    it 'shows empty message when no tasks' do
      TaskManager::Models::Task.delete_all
      expect { cli.list }.to output(/No tasks found/).to_stdout
    end
  end

  describe '#show' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'pending',
        due_date: Date.today + 1,
        tags: %w[work important],
        priority: 'high'
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'shows task details' do
      expect { cli.show('task-123') }.to output(/Test Task/).to_stdout
      expect { cli.show('task-123') }.to output(/Test Description/).to_stdout
      expect { cli.show('task-123') }.to output(/high/).to_stdout
    end

    it 'handles task not found' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:find_task_by_id).and_raise(
        TaskManager::TaskNotFoundError.new("task 'nonexistent' not found")
      )

      expect { cli.show('nonexistent') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#complete' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'pending'
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'completes a task' do
      cli.complete('task-123')
      task.reload
      expect(task.status).to eq('completed')
      expect(task.completed_at).not_to be_nil
    end

    it 'handles task not found' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:complete_task).and_raise(
        TaskManager::TaskNotFoundError.new("task 'nonexistent' not found")
      )

      expect { cli.complete('nonexistent') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#reopen' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'completed',
        completed_at: Time.now
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'reopens a task' do
      cli.reopen('task-123')
      task.reload
      expect(task.status).to eq('pending')
      expect(task.completed_at).to be_nil
    end

    it 'handles task not found' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:reopen_task).and_raise(
        TaskManager::TaskNotFoundError.new("task 'nonexistent' not found")
      )

      expect { cli.reopen('nonexistent') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#edit' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Original Title',
        description: 'Original Description',
        status: 'pending',
        due_date: Date.today + 1,
        tags: ['original'],
        priority: 'low'
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'edits task title' do
      cli.options = { title: 'New Title' }
      cli.edit('task-123')
      task.reload
      expect(task.title).to eq('New Title')
    end

    it 'edits task description' do
      cli.options = { description: 'New Description' }
      cli.edit('task-123')
      task.reload
      expect(task.description).to eq('New Description')
    end

    it 'edits task due date' do
      cli.options = { due_date: '2025-06-25' }
      cli.edit('task-123')
      task.reload
      expect(task.due_date).to eq(Date.parse('2025-06-25'))
    end

    it 'clears due date with nil' do
      cli.options = { due_date: 'nil' }
      cli.edit('task-123')
      task.reload
      expect(task.due_date).to be_nil
    end

    it 'edits task tags' do
      cli.options = { tags: %w[new tags] }
      cli.edit('task-123')
      task.reload
      expect(task.tags).to match_array(%w[new tags])
    end

    it 'clears tags with none' do
      cli.options = { tags: ['none'] }
      cli.edit('task-123')
      task.reload
      expect(task.tags).to be_empty
    end

    it 'edits task priority' do
      cli.options = { priority: 'high' }
      cli.edit('task-123')
      task.reload
      expect(task.priority).to eq('high')
    end

    it 'clears priority with nil' do
      cli.options = { priority: 'nil' }
      cli.edit('task-123')
      task.reload
      expect(task.priority).to be_nil
    end

    it 'marks task as completed' do
      cli.options = { completed: true }
      cli.edit('task-123')
      task.reload
      expect(task.status).to eq('completed')
    end

    it 'marks task as pending' do
      task.update(status: 'completed')
      cli.options = { pending: true }
      cli.edit('task-123')
      task.reload
      expect(task.status).to eq('pending')
    end

    it 'handles no attributes provided' do
      cli.options = {}
      expect { cli.edit('task-123') }.to output(/No attributes provided/).to_stdout
    end

    it 'handles task not found' do
      cli.options = { title: 'New Title' }
      allow(cli.instance_variable_get(:@task_service)).to receive(:update_task).and_raise(
        TaskManager::TaskNotFoundError.new("task 'nonexistent' not found")
      )

      expect { cli.edit('nonexistent') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#delete' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'pending'
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'deletes task when confirmed' do
      allow(cli.instance_variable_get(:@prompt)).to receive(:yes?).and_return(true)

      expect { cli.delete('task-123') }.to change { TaskManager::Models::Task.count }.by(-1)
    end

    it 'cancels deletion when not confirmed' do
      allow(cli.instance_variable_get(:@prompt)).to receive(:yes?).and_return(false)

      expect { cli.delete('task-123') }.not_to(change { TaskManager::Models::Task.count })
      expect { cli.delete('task-123') }.to output(/Deletion cancelled/).to_stdout
    end

    it 'handles task not found' do
      allow(cli.instance_variable_get(:@prompt)).to receive(:yes?).and_return(true)
      allow(cli.instance_variable_get(:@task_service)).to receive(:delete_task).and_raise(
        TaskManager::TaskNotFoundError.new("task 'nonexistent' not found")
      )

      expect { cli.delete('nonexistent') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#export' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'pending',
        due_date: Date.today + 1,
        tags: ['work'],
        priority: 'high'
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'exports tasks to CSV' do
      filename = 'test_export.csv'
      cli.export('csv', filename)

      expect(File.exist?(filename)).to be true
      expect(File.read(filename)).to include('Test Task')
      expect(File.read(filename)).to include('high')

      File.delete(filename)
    end

    it 'handles unsupported format' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:export_tasks).and_raise(
        TaskManager::InvalidInputError.new('unsupported export format: invalid')
      )

      expect { cli.export('invalid', 'test.txt') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#import' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'imports tasks from CSV' do
      csv_content = <<~CSV
        Title,Description,Status,Due Date,Tags,Priority,Created At,Completed At
        Imported Task,Test import,pending,2025-06-20,work;important,high,2025-06-12 10:00:00,
      CSV

      filename = 'test_import.csv'
      File.write(filename, csv_content)

      expect { cli.import('csv', filename) }.to change { TaskManager::Models::Task.count }.by(1)

      task = TaskManager::Models::Task.last
      expect(task.title).to eq('Imported Task')
      expect(task.user_id).to eq(user_id)

      File.delete(filename)
    end

    it 'handles unsupported format' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:import_tasks).and_raise(
        TaskManager::InvalidInputError.new('unsupported import format: invalid')
      )

      expect { cli.import('invalid', 'test.txt') }.to output(/ERROR/).to_stdout
    end
  end

  describe '#whoami' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    it 'shows current user when logged in' do
      cli.current_user = user
      expect { cli.whoami }.to output(/You are currently logged in as:.*testuser/).to_stdout
    end

    it 'shows not logged in message' do
      expect { cli.whoami }.to output(/You are not logged in/).to_stdout
    end
  end

  describe 'authentication' do
    it 'requires authentication for protected commands' do
      expect { cli.add('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.list }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.show('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.complete('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.reopen('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.edit('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.delete('test') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.export('csv', 'test.csv') }.to raise_error(Thor::Error, /You must be logged in/)
      expect { cli.import('csv', 'test.csv') }.to raise_error(Thor::Error, /You must be logged in/)
    end
  end

  describe 'error handling' do
    let!(:user) do
      TaskManager::Models::User.create!(
        id: user_id,
        username: username,
        password_digest: BCrypt::Password.create(password)
      )
    end

    before do
      cli.current_user = user
      cli.instance_variable_get(:@task_service).set_current_user_id(user_id)
    end

    it 'handles unexpected errors gracefully' do
      allow(cli.instance_variable_get(:@task_service)).to receive(:add_task).and_raise(StandardError.new('Unexpected error'))

      expect { cli.add('test') }.to output(/An unexpected error occurred/).to_stdout
      expect(cli.instance_variable_get(:@logger)).to have_received(:fatal).with(/Failed to add task/)
    end
  end
end
