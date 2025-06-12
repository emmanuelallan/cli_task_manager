require 'spec_helper'
require_relative '../../../../lib/task_manager/services/task_service'
require_relative '../../../../lib/task_manager/notifications/system_notifier'
require_relative '../../../../lib/task_manager/notifications/notifier'
require_relative '../../../../lib/task_manager/models/task'

RSpec.describe TaskManager::Services::TaskService do
  let(:task_service) { described_class.new }
  let(:user_id) { 'test-user-123' }
  let(:system_notifier) { TaskManager::Notifications::SystemNotifier.new }
  let(:notifier) { TaskManager::Notifications::Notifier.new }

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    TaskManager::Models::Task.delete_all
    TaskManager::Models::User.delete_all

    # Set up task service with notifications
    task_service.set_current_user_id(user_id)

    # Add system notifier as observer
    notifier.add_observer(system_notifier)

    # Mock the system notifier to avoid actual notifications during tests
    allow(system_notifier).to receive(:update)
  end

  describe 'notification integration' do
    describe '#complete_task' do
      let!(:task) do
        TaskManager::Models::Task.create!(
          id: 'task-123',
          user_id: user_id,
          title: 'Test Task',
          description: 'Test Description',
          status: 'pending'
        )
      end

      it 'triggers task_completed notification' do
        expect(notifier).to receive(:update).with(task, :task_completed)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.complete_task('task-123')
      end

      it 'sends notification to system notifier' do
        expect(system_notifier).to receive(:update).with(instance_of(TaskManager::Models::Task), :task_completed)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.complete_task('task-123')
      end
    end

    describe '#reopen_task' do
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

      it 'triggers task_reopened notification' do
        expect(notifier).to receive(:update).with(task, :task_reopened)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.reopen_task('task-123')
      end
    end

    describe '#add_task' do
      it 'triggers task_created notification' do
        expect(notifier).to receive(:update).with(instance_of(TaskManager::Models::Task), :task_created)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.add_task(
          title: 'New Task',
          description: 'New Description'
        )
      end
    end

    describe '#delete_task' do
      let!(:task) do
        TaskManager::Models::Task.create!(
          id: 'task-123',
          user_id: user_id,
          title: 'Test Task',
          description: 'Test Description',
          status: 'pending'
        )
      end

      it 'triggers task_deleted notification' do
        expect(notifier).to receive(:update).with(task, :task_deleted)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.delete_task('task-123')
      end
    end

    describe 'overdue task notifications' do
      let!(:overdue_task) do
        TaskManager::Models::Task.create!(
          id: 'overdue-task',
          user_id: user_id,
          title: 'Overdue Task',
          description: 'Overdue Description',
          status: 'pending',
          due_date: Date.today - 1
        )
      end

      it 'triggers task_overdue_check notification for overdue tasks' do
        expect(notifier).to receive(:update).with(overdue_task, :task_overdue_check)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        # Trigger overdue check (this would typically be called by a background job)
        task_service.check_overdue_tasks
      end

      it 'does not trigger overdue notification for completed tasks' do
        overdue_task.update(status: 'completed')

        expect(notifier).not_to receive(:update).with(overdue_task, :task_overdue_check)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.check_overdue_tasks
      end
    end

    describe 'due soon notifications' do
      let!(:due_soon_task) do
        TaskManager::Models::Task.create!(
          id: 'due-soon-task',
          user_id: user_id,
          title: 'Due Soon Task',
          description: 'Due Soon Description',
          status: 'pending',
          due_date: Date.today + 1
        )
      end

      it 'triggers task_due_soon notification for tasks due within 24 hours' do
        expect(notifier).to receive(:update).with(due_soon_task, :task_due_soon)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        # Trigger due soon check
        task_service.check_due_soon_tasks
      end

      it 'does not trigger due soon notification for completed tasks' do
        due_soon_task.update(status: 'completed')

        expect(notifier).not_to receive(:update).with(due_soon_task, :task_due_soon)

        # Mock the notifier in the task service
        allow(task_service).to receive(:notifier).and_return(notifier)

        task_service.check_due_soon_tasks
      end
    end
  end

  describe 'notification configuration' do
    it 'initializes with a notifier' do
      expect(task_service.notifier).to be_a(TaskManager::Notifications::Notifier)
    end

    it 'allows adding observers to the notifier' do
      expect(task_service.notifier.count_observers).to eq(0)

      task_service.notifier.add_observer(system_notifier)

      expect(task_service.notifier.count_observers).to eq(1)
    end

    it 'allows removing observers from the notifier' do
      task_service.notifier.add_observer(system_notifier)
      expect(task_service.notifier.count_observers).to eq(1)

      task_service.notifier.delete_observer(system_notifier)
      expect(task_service.notifier.count_observers).to eq(0)
    end
  end

  describe 'notification error handling' do
    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Test Task',
        description: 'Test Description',
        status: 'pending'
      )
    end

    it 'handles notification errors gracefully' do
      # Mock the notifier to raise an error
      allow(task_service).to receive(:notifier).and_return(notifier)
      allow(notifier).to receive(:update).and_raise(StandardError.new('Notification failed'))

      # The task operation should still succeed even if notification fails
      expect { task_service.complete_task('task-123') }.not_to raise_error

      # Verify the task was actually completed
      task.reload
      expect(task.status).to eq('completed')
    end

    it 'logs notification errors' do
      # Mock the notifier to raise an error
      allow(task_service).to receive(:notifier).and_return(notifier)
      allow(notifier).to receive(:update).and_raise(StandardError.new('Notification failed'))

      # Mock logger to verify error logging
      logger = double('logger')
      allow(task_service).to receive(:logger).and_return(logger)
      expect(logger).to receive(:error).with(/Notification failed/)

      task_service.complete_task('task-123')
    end
  end

  describe 'notification content' do
    let!(:task) do
      TaskManager::Models::Task.create!(
        id: 'task-123',
        user_id: user_id,
        title: 'Important Task',
        description: 'This is an important task',
        status: 'pending',
        due_date: Date.today + 1,
        priority: 'high',
        tags: %w[work urgent]
      )
    end

    it 'includes task details in notifications' do
      expect(system_notifier).to receive(:update).with(
        instance_of(TaskManager::Models::Task),
        :task_completed
      ) do |task_arg, _event_type|
        expect(task_arg.title).to eq('Important Task')
        expect(task_arg.priority).to eq('high')
        expect(task_arg.tags).to include('work', 'urgent')
      end

      # Mock the notifier in the task service
      allow(task_service).to receive(:notifier).and_return(notifier)

      task_service.complete_task('task-123')
    end
  end
end
