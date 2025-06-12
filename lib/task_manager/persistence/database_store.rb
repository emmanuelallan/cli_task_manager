require 'active_record'
require 'fileutils'
require_relative '../config/application_config'

module TaskManager
  module Persistence
    class DatabaseStore
      class << self
        def establish_connection
          config = TaskManager::Config::ApplicationConfig.instance
          db_path = File.join(config.data_directory, 'task_manager.db')
          
          # Ensure database directory exists
          FileUtils.mkdir_p(File.dirname(db_path))

          # Establish connection
          ActiveRecord::Base.establish_connection(
            adapter: 'sqlite3',
            database: db_path
          )

          # Run migrations
          run_migrations
        end

        private

        def run_migrations
          # Create users table if it doesn't exist
          unless ActiveRecord::Base.connection.table_exists?(:users)
            ActiveRecord::Base.connection.create_table :users, id: false do |t|
              t.string :id, null: false, primary_key: true
              t.string :username, null: false
              t.string :password_digest, null: false
              t.json :preferences, default: '{}'
              t.timestamps null: false
            end

            # Add indexes
            ActiveRecord::Base.connection.add_index :users, :id, unique: true
            ActiveRecord::Base.connection.add_index :users, :username, unique: true
          end

          # Create tasks table if it doesn't exist
          unless ActiveRecord::Base.connection.table_exists?(:tasks)
            ActiveRecord::Base.connection.create_table :tasks, id: false do |t|
              t.string :id, null: false, primary_key: true
              t.string :user_id, null: false
              t.string :title, null: false
              t.text :description
              t.string :status, default: 'pending'
              t.date :due_date
              t.json :tags, default: '[]'
              t.datetime :completed_at
              t.string :priority
              t.string :recurrence
              t.string :parent_task_id
              t.timestamps null: false
            end

            # Add indexes
            ActiveRecord::Base.connection.add_index :tasks, :id, unique: true
            ActiveRecord::Base.connection.add_index :tasks, :user_id
            ActiveRecord::Base.connection.add_index :tasks, :status
            ActiveRecord::Base.connection.add_index :tasks, :due_date
          end
        end
      end

      def initialize
        self.class.establish_connection
      end
    end
  end
end 