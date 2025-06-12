require 'singleton'
require 'yaml'
require 'fileutils'
require_relative '../core/errors'

module TaskManager
  module Config
    # manages application-wide configuration using Singleton pattern
    class ApplicationConfig
      include Singleton

      attr_reader :data_directory, :log_file_path, :default_file_format,
                  :default_sort_order, :session_file_path, :config_hash

      private_class_method :new

      # initializes configuration and loads default settings
      def initialize
        @config_hash = load_default_config
        # TODO: Implement user-specific config overrides

        set_derived_paths
        @current_session_user_id = load_session
      end

      # loads and validates default configuration from YAML
      # @raise [TaskManager::FileError] if config file is missing or invalid
      # @return [Hash] Configuration data
      def load_default_config
        config_path = File.expand_path('application.yml', File.dirname(__FILE__))
        unless File.exist?(config_path)
          raise TaskManager::FileError, "Default application config file not found at: #{config_path}"
        end

        begin
          YAML.load_file(config_path)
        rescue Psych::SyntaxError => e
          raise TaskManager::FileError, "Failed to parse application config file: #{e.message}"
        rescue => e
          raise TaskManager::FileError, "An unexpected error occurred loading config: #{e.message}"
        end
      end

      # creates required directories and sets up path configurations
      def set_derived_paths
        data_dir_name = @config_hash.fetch('data_directory_name', '.task_manager_app')
        log_file_name = @config_hash.fetch('log_file_name', 'app.log')
        session_file_name = @config_hash.fetch('session_file_name', 'session.yml')

        @data_directory = File.join(Dir.home, data_dir_name)
        @log_file_path  = File.join(@data_directory, log_file_name)
        @session_file_path = File.join(@data_directory, session_file_name)
        @default_file_format = @config_hash.fetch('default_file_format', 'json').to_sym
        @default_sort_order = @config_hash.fetch('default_sort_order', 'created_at').to_sym

        FileUtils.mkdir_p(@data_directory)
      end

      # Session Management Methods

      # @return [String, nil] Current user ID from session
      def get_session_user_id
        @current_session_user_id
      end

      # updates session with new user ID
      # @param user_id [String] User ID to store in session
      def set_session_user_id(user_id)
        @current_session_user_id = user_id
        save_session(user_id)
      end

      # removes current session data
      def clear_session
        @current_session_user_id = nil
        save_session(nil)
      end

      private

      # loads existing session data from file
      # @return [String, nil] Stored user ID or nil if no session exists
      def load_session
        return nil unless File.exist?(@session_file_path)
        begin
          session_data = YAML.load_file(@session_file_path)
          session_data&.fetch('current_user_id', nil)
        rescue StandardError => e
          nil
        end
      end

      # persists session data to file
      # @param user_id [String, nil] User ID to save
      def save_session(user_id)
        session_data = { 'current_user_id' => user_id }
        File.write(@session_file_path, session_data.to_yaml)
      rescue StandardError => e
        puts "Error saving session: #{e.message}".colorize(:red)
      end

      public

      # retrieves a configuration value by key
      # @param key [String] Configuration key
      # @return [Object] Value for the given key
      def get(key)
        @config_hash[key.to_s]
      end

      # Usage Examples:
      # TaskManager::Config::ApplicationConfig.instance.data_directory
      # TaskManager::Config::ApplicationConfig.instance.default_file_format
      # TaskManager::Config::ApplicationConfig.instance.get('log_file_name')
    end
  end
end