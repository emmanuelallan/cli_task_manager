require 'bcrypt'
require 'active_record'
require_relative '../persistence/database_store'

module TaskManager
  module Models
    # manages user authentication and preferences
    class User < ActiveRecord::Base
      # Ensure database connection is established
      TaskManager::Persistence::DatabaseStore.establish_connection

      self.table_name = 'users'
      self.primary_key = 'id'

      # Validations
      validates :username, presence: true, uniqueness: { case_sensitive: false }
      validates :password_digest, presence: true

      # Use new ActiveRecord 8+ attribute API for preferences
      attribute :preferences, :json, default: {}

      # Callbacks
      before_create :set_uuid

      # creates user instance from hash data
      # @param hash [Hash] user data
      # @return [User] new user instance
      def self.from_h(hash)
        new(
          username: hash['username'],
          password_digest: hash['password_digest'],
          preferences: hash.fetch('preferences', {})
        )
      end

      # sets encrypted password
      # @param plain_password [String] raw password to encrypt
      def set_password(plain_password)
        self.password_digest = BCrypt::Password.create(plain_password).to_s
      end

      # validates user password
      # @param plain_password [String] password to check
      # @return [Boolean] true if password matches
      def authenticate(plain_password)
        BCrypt::Password.new(password_digest) == plain_password
      rescue BCrypt::Errors::InvalidHash
        false
      end

      # converts user to hash for storage
      # @return [Hash] user data
      def to_h
        {
          'id' => id,
          'username' => username,
          'password_digest' => password_digest,
          'created_at' => created_at&.iso8601,
          'preferences' => preferences
        }
      end

      private

      def set_uuid
        self.id = SecureRandom.uuid unless id.present?
      end
    end
  end
end
