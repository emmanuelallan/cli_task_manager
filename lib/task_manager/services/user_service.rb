# lib/task_manager/services/user_service.rb
require 'securerandom'

require_relative '../models/user'
require_relative '../persistence/database_store'
require_relative '../core/errors'

module TaskManager
  module Services
    # handles user authentication and management
    class UserService
      # sets up service
      def initialize
        # No need for db_store parameter as we're using ActiveRecord directly
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

        user = TaskManager::Models::User.new(username: username)
        user.set_password(password)
        
        if user.save
          user
        else
          raise TaskManager::InvalidInputError, "failed to create user: #{user.errors.full_messages.join(', ')}"
        end
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
        TaskManager::Models::User.find_by(id: id)
      end

      # finds user by username
      # @param username [String] username to find
      # @return [User, nil] matching user or nil
      def find_user_by_username(username)
        TaskManager::Models::User.find_by('LOWER(username) = ?', username.downcase)
      end

      # gets copy of users list
      # @return [Array<User>] list of users
      def get_all_users
        TaskManager::Models::User.all
      end
    end
  end
end