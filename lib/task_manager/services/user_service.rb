# lib/task_manager/services/user_service.rb
require 'securerandom'

require_relative '../models/user'
require_relative '../persistence/file_store'
require_relative '../core/errors'

module TaskManager
  module Services
    # handles user authentication and management
    class UserService
      attr_reader :file_store
      attr_accessor :users

      # sets up service with storage
      # @param file_store [FileStore] storage handler
      def initialize(file_store:)
        @file_store = file_store
        @users = @file_store.load_users
        puts "loaded #{@users.size} users"
      end

      # creates new user account
      # @param username [String] unique username
      # @param password [String] user password
      # @return [User] new user
      # @raise [UsernameAlreadyExistsError] if username taken
      def register_user(username, password)
        if find_user_by_username(username)
          raise TaskManager::UsernameAlreadyExistsError, "username '#{username}' is already taken"
        end

        new_id = SecureRandom.uuid
        user = TaskManager::Models::User.new(id: new_id, username: username)
        user.set_password(password)
        
        @users << user
        save_all_users
        user
      end

      # validates user credentials
      # @param username [String] username to check
      # @param password [String] password to verify
      # @return [User] authenticated user
      # @raise [UserNotFoundError] if user not found
      # @raise [AuthenticationError] if password invalid
      def authenticate_user(username, password)
        user = find_user_by_username(username)

        unless user
          raise TaskManager::UserNotFoundError, "user '#{username}' not found"
        end

        if user.authenticate(password)
          user
        else
          raise TaskManager::AuthenticationError, "incorrect password for user '#{username}'"
        end
      end

      # finds user by id
      # @param id [String] user identifier
      # @return [User, nil] matching user or nil
      def find_user_by_id(id)
        @users.find { |user| user.id == id }
      end

      # finds user by username
      # @param username [String] username to find
      # @return [User, nil] matching user or nil
      def find_user_by_username(username)
        @users.find { |user| user.username.downcase == username.downcase }
      end

      # saves users to storage
      def save_all_users
        @file_store.save_users(@users)
      end

      # gets copy of users list
      # @return [Array<User>] list of users
      def get_all_users
        @users.dup
      end
    end
  end
end