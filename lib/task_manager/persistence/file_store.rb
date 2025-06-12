require 'fileutils'
require 'json'
require 'yaml'

require_relative '../models/task'
require_relative '../models/user'
require_relative '../core/errors'
require_relative '../config/application_config'

module TaskManager
  module Persistence
    # handles storage and retrieval of tasks and users
    class FileStore
      attr_reader :data_dir, :file_format, :tasks_file, :users_file

      # initializes storage paths from config
      def initialize
        config = TaskManager::Config::ApplicationConfig.instance
        @data_dir = File.expand_path(config.data_directory)
        @file_format = config.default_file_format
        @tasks_file = File.join(@data_dir, "tasks.#{@file_format}")
        @users_file = File.join(@data_dir, "users.#{@file_format}")

        ensure_data_dir_exists
      end

      # retrieves tasks from storage
      # @return [Array<Task>] list of tasks
      # @raise [FileError] if load fails
      def load_tasks
        load_data(@tasks_file).map { |hash| TaskManager::Models::Task.from_h(hash) }
      rescue TaskManager::FileError => e
        puts "warning: starting with empty task list - #{e.message}"
        []
      end

      # persists tasks to storage
      # @param tasks [Array<Task>] tasks to save
      # @raise [FileError] if save fails
      def save_tasks(tasks)
        data_to_save = tasks.map(&:to_h)
        save_data(@tasks_file, data_to_save)
      end

      # retrieves users from storage
      # @return [Array<User>] list of users
      # @raise [FileError] if load fails
      def load_users
        load_data(@users_file).map { |hash| TaskManager::Models::User.from_h(hash) }
      rescue TaskManager::FileError => e
        puts "warning: starting with no users - #{e.message}"
        []
      end

      # persists users to storage
      # @param users [Array<User>] users to save
      # @raise [FileError] if save fails
      def save_users(users)
        data_to_save = users.map(&:to_h)
        save_data(@users_file, data_to_save)
      end

      private

      # creates data directory if needed
      # @raise [FileError] if creation fails
      def ensure_data_dir_exists
        FileUtils.mkdir_p(@data_dir) unless File.directory?(@data_dir)
      rescue StandardError => e
        raise TaskManager::FileError, "failed to create data directory: #{e.message}"
      end

      # loads data from file
      # @param filepath [String] path to file
      # @return [Array<Hash>] loaded data
      # @raise [FileError] if load fails
      def load_data(filepath)
        return [] unless File.exist?(filepath)

        file_content = File.read(filepath)
        return [] if file_content.strip.empty?

        parsed_data =
          case @file_format
          when :json then JSON.parse(file_content)
          when :yaml then YAML.safe_load(file_content, permitted_classes: [Date, Time, Symbol])
          else raise TaskManager::FileError, "unsupported format: #{@file_format}"
          end

        raise TaskManager::FileError, "invalid data format in #{filepath}" unless parsed_data.is_a?(Array)

        parsed_data
      rescue JSON::ParserError, Psych::SyntaxError => e
        raise TaskManager::FileError, "failed to parse data: #{e.message}"
      rescue StandardError => e
        raise TaskManager::FileError, "unexpected error loading data: #{e.message}"
      end

      # saves data to file atomically
      # @param filepath [String] path to file
      # @param data [Array<Hash>] data to save
      # @raise [FileError] if save fails
      def save_data(filepath, data)
        serialized_data =
          case @file_format
          when :json then JSON.pretty_generate(data)
          when :yaml then YAML.dump(data)
          else raise TaskManager::FileError, "unsupported format: #{@file_format}"
          end

        temp_filepath = "#{filepath}.tmp"
        begin
          File.write(temp_filepath, serialized_data)
          FileUtils.mv(temp_filepath, filepath)
        rescue StandardError => e
          File.delete(temp_filepath) if File.exist?(temp_filepath)
          raise TaskManager::FileError, "failed to save data: #{e.message}"
        end
      end
    end
  end
end
