require 'spec_helper'
require 'active_record'
require 'fileutils'
require_relative '../../../../lib/task_manager/persistence/database_store'

RSpec.describe TaskManager::Persistence::DatabaseStore do
  let(:config) { instance_double(TaskManager::Config::ApplicationConfig) }
  let(:data_directory) { File.join(ENV['TMPDIR'] || '/tmp', 'task_manager_test') }
  let(:db_path) { File.join(data_directory, 'task_manager.db') }

  before do
    # Mock the ApplicationConfig
    allow(TaskManager::Config::ApplicationConfig).to receive(:instance).and_return(config)
    allow(config).to receive(:data_directory).and_return(data_directory)

    # Clean up test database before each test
    FileUtils.rm_rf(data_directory)
    FileUtils.mkdir_p(data_directory)
  end

  after do
    # Clean up test database after each test
    FileUtils.rm_rf(data_directory)
  end

  describe '.establish_connection' do
    it 'creates the database directory if it does not exist' do
      expect(FileUtils).to receive(:mkdir_p).with(File.dirname(db_path))
      described_class.establish_connection
    end

    it 'establishes a connection to the SQLite database' do
      expect(ActiveRecord::Base).to receive(:establish_connection).with(
        adapter: 'sqlite3',
        database: db_path
      )
      described_class.establish_connection
    end

    it 'creates the tasks table with correct schema' do
      described_class.establish_connection
      
      # Verify tasks table exists
      expect(ActiveRecord::Base.connection.table_exists?(:tasks)).to be true
      
      # Verify columns
      columns = ActiveRecord::Base.connection.columns(:tasks).map(&:name)
      expect(columns).to include(
        'id', 'user_id', 'title', 'description', 'status',
        'due_date', 'tags', 'created_at', 'completed_at',
        'priority', 'recurrence', 'parent_task_id'
      )

      # Verify indexes
      indexes = ActiveRecord::Base.connection.indexes(:tasks).map(&:name)
      expect(indexes).to include(
        'index_tasks_on_id',
        'index_tasks_on_user_id',
        'index_tasks_on_status',
        'index_tasks_on_due_date'
      )
    end

    it 'creates the users table with correct schema' do
      described_class.establish_connection
      
      # Verify users table exists
      expect(ActiveRecord::Base.connection.table_exists?(:users)).to be true
      
      # Verify columns
      columns = ActiveRecord::Base.connection.columns(:users).map(&:name)
      expect(columns).to include(
        'id', 'username', 'password_digest', 'created_at', 'preferences'
      )

      # Verify indexes
      indexes = ActiveRecord::Base.connection.indexes(:users).map(&:name)
      expect(indexes).to include(
        'index_users_on_id',
        'index_users_on_username'
      )
    end
  end

  describe '#initialize' do
    it 'establishes database connection on initialization' do
      expect(described_class).to receive(:establish_connection)
      described_class.new
    end
  end

  describe 'database operations' do
    before do
      described_class.establish_connection
    end

    it 'allows creating and retrieving a task' do
      task = ActiveRecord::Base.connection.execute(<<-SQL)
        INSERT INTO tasks (id, user_id, title, description, status, created_at)
        VALUES ('test-id', 'user-1', 'Test Task', 'Test Description', 'pending', datetime('now'))
      SQL

      result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT * FROM tasks WHERE id = 'test-id'
      SQL

      expect(result.first['title']).to eq('Test Task')
      expect(result.first['description']).to eq('Test Description')
      expect(result.first['status']).to eq('pending')
    end

    it 'allows creating and retrieving a user' do
      user = ActiveRecord::Base.connection.execute(<<-SQL)
        INSERT INTO users (id, username, password_digest, created_at)
        VALUES ('user-1', 'testuser', 'hashed_password', datetime('now'))
      SQL

      result = ActiveRecord::Base.connection.execute(<<-SQL)
        SELECT * FROM users WHERE id = 'user-1'
      SQL

      expect(result.first['username']).to eq('testuser')
      expect(result.first['password_digest']).to eq('hashed_password')
    end
  end
end
