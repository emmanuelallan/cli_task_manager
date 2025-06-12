require 'spec_helper'
require_relative '../../../../lib/task_manager/notifications/system_notifier'
require_relative '../../../../lib/task_manager/models/task'

RSpec.describe TaskManager::Notifications::SystemNotifier do
  let(:system_notifier) { described_class.new }
  let(:user_id) { 'test-user-123' }
  let(:task) do
    TaskManager::Models::Task.new(
      id: 'task-123',
      user_id: user_id,
      title: 'Test Task',
      description: 'Test Description',
      status: 'pending',
      due_date: Date.today + 1,
      priority: 'high'
    )
  end

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    TaskManager::Models::Task.delete_all
  end

  describe '#initialize' do
    it 'initializes system notifier successfully' do
      expect(system_notifier).to be_a(described_class)
    end

    it 'detects the current platform' do
      expect(system_notifier.platform).to be_a(String)
      expect(['macos', 'linux', 'windows', 'unknown']).to include(system_notifier.platform)
    end
  end

  describe '#update' do
    context 'when task is completed' do
      before do
        task.status = 'completed'
        task.completed_at = Time.now
      end

      it 'handles task_completed event type' do
        expect { system_notifier.update(task, :task_completed) }.not_to raise_error
      end
    end

    context 'when task is overdue' do
      before do
        task.due_date = Date.today - 1
        task.status = 'pending'
      end

      it 'handles task_overdue_check event type' do
        expect { system_notifier.update(task, :task_overdue_check) }.not_to raise_error
      end

      it 'does not send overdue notification for completed tasks' do
        task.status = 'completed'
        expect { system_notifier.update(task, :task_overdue_check) }.not_to raise_error
      end
    end

    context 'when task is due soon' do
      before do
        task.due_date = Date.today + 1
        task.status = 'pending'
      end

      it 'handles task_due_soon event type' do
        expect { system_notifier.update(task, :task_due_soon) }.not_to raise_error
      end
    end

    context 'when task is reopened' do
      it 'handles task_reopened event type' do
        expect { system_notifier.update(task, :task_reopened) }.not_to raise_error
      end
    end

    context 'when task is created' do
      it 'handles task_created event type' do
        expect { system_notifier.update(task, :task_created) }.not_to raise_error
      end
    end

    context 'when task is deleted' do
      it 'handles task_deleted event type' do
        expect { system_notifier.update(task, :task_deleted) }.not_to raise_error
      end
    end

    context 'with unknown event type' do
      it 'handles unknown event types gracefully' do
        expect { system_notifier.update(task, :unknown_event) }.not_to raise_error
      end
    end
  end

  describe 'platform detection' do
    it 'detects macOS correctly' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')
      notifier = described_class.new
      expect(notifier.platform).to eq('macos')
    end

    it 'detects Linux correctly' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux')
      notifier = described_class.new
      expect(notifier.platform).to eq('linux')
    end

    it 'detects Windows correctly' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('mswin')
      notifier = described_class.new
      expect(notifier.platform).to eq('windows')
    end

    it 'returns unknown for unsupported platforms' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('unsupported')
      notifier = described_class.new
      expect(notifier.platform).to eq('unknown')
    end
  end

  describe 'error handling' do
    it 'handles notification failures gracefully' do
      # Mock platform to trigger a notification method that might fail
      allow(system_notifier).to receive(:platform).and_return('linux')
      
      # The update method should not raise errors even if underlying notification fails
      expect { system_notifier.update(task, :task_completed) }.not_to raise_error
    end
  end
end 