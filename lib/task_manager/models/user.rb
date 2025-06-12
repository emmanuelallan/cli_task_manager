require 'bcrypt'

module TaskManager
    module Models
        # manages user authentication and preferences
        class User
            attr_reader :id, :username, :created_at
            attr_accessor :password_digest, :preferences

            # creates user instance from hash data
            # @param hash [Hash] user data
            # @return [User] new user instance
            def self.from_h(hash)
                new(
                    id: hash['id'],
                    username: hash['username'],
                    password_digest: hash['password_digest'],
                    created_at: Time.parse(hash['created_at']),
                    preferences: hash.fetch('preferences', {})
                )
            end

            # initializes new user
            # @param id [String] unique identifier
            # @param username [String] user's login name
            # @param password_digest [String] encrypted password
            # @param created_at [Time] account creation time
            # @param preferences [Hash] user settings
            def initialize(id:, username:, password_digest: nil, created_at: Time.now, preferences: {})
                @id = id
                @username = username
                @password_digest = password_digest
                @created_at = created_at
                @preferences = preferences
            end

            # sets encrypted password
            # @param plain_password [String] raw password to encrypt
            def set_password(plain_password)
                @password_digest = BCrypt::Password.create(plain_password).to_s
            end

            # validates user password
            # @param plain_password [String] password to check
            # @return [Boolean] true if password matches
            def authenticate(plain_password)
                BCrypt::Password.new(@password_digest) == plain_password
            rescue BCrypt::Errors::InvalidHash
                false
            end

            # converts user to hash for storage
            # @return [Hash] user data
            def to_h
                {
                    'id' => @id,
                    'username' => @username,
                    'password_digest' => @password_digest,
                    'created_at' => @created_at.iso8601,
                    'preferences' => @preferences
                }
            end
        end
    end
end