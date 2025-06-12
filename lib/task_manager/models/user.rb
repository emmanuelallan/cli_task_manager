require 'bcrypt'

module TaskManager
    module Models
        class User
            attr_reader :id, :username, :created_at
            attr_accessor :password_digest, :preferences

            def self.from_h(hash)
                new(
                    id: hash['id'],
                    username: hash['username'],
                    password_digest: hash['password_digest'],
                    created_at: Time.parse(hash['created_at']),
                    preferences: hash.fetch('preferences', {})

                )
            end

            def initialize(id:, username:, password_digest: nil, created_at: Time.now, preferences: {})
                @id = id
                @username = username
                @password_digest = password_digest
                @created_at = created_at
                @preferences = preferences
            end

            def set_password(plain_password)
                @password_digest = BCrypt::Password.create(plain_password).to_s
            end

            def authenticate(plain_password)
                BCrypt::Password.new(@password_digest) == plain_password

            rescue BCrypt::Errors:InvalidHash
                false
            end

            def to_h
                {
                    'id' => @id,
                    'username' => @username
                    'password_digest' => @password_digest
                    'created_at' => @created_at
                    'preferences' => @preferences
                }
            end
        end
    end
end