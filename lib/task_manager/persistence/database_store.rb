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

          # ensures database directory exists
          FileUtils.mkdir_p(File.dirname(db_path))

          # establishes connection
          ActiveRecord::Base.establish_connection(
            adapter: 'sqlite3',
            database: db_path
          )

          run_migrations
        end

        def reset_database
          config = TaskManager::Config::ApplicationConfig.instance
          db_path = File.join(config.data_directory, 'task_manager.db')

          # remove existing database
          FileUtils.rm_f(db_path)

          # re-establish connection and run migrations
          establish_connection
        end

        private

        def run_migrations
          # creates users table if it doesn't exist
          unless ActiveRecord::Base.connection.table_exists?(:users)
            ActiveRecord::Base.connection.create_table :users, id: false do |t|
              t.string :id, null: false, primary_key: true
              t.string :username, null: false
              t.string :password_digest, null: false
              t.json :preferences, default: '{}'
              t.timestamps null: false
            end

            # adds indexes
            ActiveRecord::Base.connection.add_index :users, :id, unique: true
            ActiveRecord::Base.connection.add_index :users, :username, unique: true
          end

          # creates tasks table if it doesn't exist
          if ActiveRecord::Base.connection.table_exists?(:tasks)
            # checks if status column exists, adds it if missing
            unless ActiveRecord::Base.connection.column_exists?(:tasks, :status)
              ActiveRecord::Base.connection.add_column :tasks, :status, :string, null: false, default: 'pending'
              ActiveRecord::Base.connection.add_index :tasks, :status
            end
          else
            ActiveRecord::Base.connection.create_table :tasks, id: false do |t|
              t.string :id, null: false, primary_key: true
              t.string :user_id, null: false
              t.string :title, null: false
              t.text :description, null: false
              t.string :status, null: false, default: 'pending'
              t.date :due_date
              t.json :tags, default: '[]'
              t.datetime :completed_at
              t.string :priority
              t.json :recurrence, default: '{}'
              t.string :parent_task_id
              t.boolean :completed, default: false
              t.timestamps null: false
            end

            # adds indexes
            ActiveRecord::Base.connection.add_index :tasks, :id, unique: true
            ActiveRecord::Base.connection.add_index :tasks, :user_id
            ActiveRecord::Base.connection.add_index :tasks, :status
            ActiveRecord::Base.connection.add_index :tasks, :due_date
            ActiveRecord::Base.connection.add_index :tasks, :priority
            ActiveRecord::Base.connection.add_index :tasks, :created_at
            ActiveRecord::Base.connection.add_index :tasks, :updated_at
          end
        end
      end

      def initialize
        self.class.establish_connection
      end
    end
  end
end
