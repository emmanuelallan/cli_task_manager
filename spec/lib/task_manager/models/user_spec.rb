require 'spec_helper'
require 'bcrypt'
require 'active_record'
require_relative '../../../../lib/task_manager/models/user'

RSpec.describe TaskManager::Models::User do
  let(:username) { 'testuser' }
  let(:password) { 'secure_password123' }
  let(:preferences) { { 'notifications' => true, 'theme' => 'dark' } }

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    described_class.delete_all
  end

  describe 'preferences' do
    it 'serializes preferences as JSON' do
      puts "\nDEBUG: Starting preferences test"
      
      # Create user with username
      user = described_class.new(username: username)
      puts "DEBUG: User after new: #{user.inspect}"
      
      # Set password
      user.set_password(password)
      puts "DEBUG: User after set_password: #{user.inspect}"
      
      # Set preferences
      user.preferences = preferences
      puts "DEBUG: User after setting preferences: #{user.inspect}"
      
      # Save user
      user.save!
      puts "DEBUG: User after save: #{user.inspect}"
      
      # Reload user from database
      reloaded_user = described_class.find(user.id)
      puts "DEBUG: Reloaded user: #{reloaded_user.inspect}"
      
      expect(reloaded_user.preferences).to eq(preferences)
    end
  end

  describe 'validations' do
    it 'requires a username' do
      user = described_class.new
      user.set_password(password)
      expect(user).not_to be_valid
      expect(user.errors[:username]).to include("can't be blank")
    end

    it 'requires a unique username (case insensitive)' do
      # Create first user
      user1 = described_class.new(username: username)
      user1.set_password(password)
      user1.save!

      # Try to create second user with same username
      user2 = described_class.new(username: username.upcase)
      user2.set_password(password)
      expect(user2).not_to be_valid
      expect(user2.errors[:username]).to include('has already been taken')
    end

    it 'requires a password_digest' do
      user = described_class.new(username: username)
      expect(user).not_to be_valid
      expect(user.errors[:password_digest]).to include("can't be blank")
    end
  end

  describe '#set_password' do
    it 'encrypts the password using BCrypt' do
      user = described_class.new(username: username)
      user.set_password(password)
      expect(user.password_digest).to be_a(String)
      expect(user.password_digest).to start_with('$2a$')
    end
  end

  describe '#authenticate' do
    let(:user) do
      u = described_class.new(username: username)
      u.set_password(password)
      u
    end

    it 'returns true for correct password' do
      expect(user.authenticate(password)).to be true
    end

    it 'returns false for incorrect password' do
      expect(user.authenticate('wrong_password')).to be false
    end

    it 'returns false for invalid password hash' do
      user.password_digest = 'invalid_hash'
      expect(user.authenticate(password)).to be false
    end
  end

  describe 'callbacks' do
    it 'generates a UUID if id is not provided' do
      user = described_class.new(username: username)
      user.set_password(password)
      user.save!
      expect(user.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'sets created_at if not provided' do
      user = described_class.new(username: username)
      user.set_password(password)
      user.save!
      expect(user.created_at).not_to be_nil
    end
  end

  describe '#to_h' do
    let(:user) do
      described_class.new(
        username: username,
        password_digest: BCrypt::Password.create(password).to_s,
        preferences: preferences
      )
    end

    it 'converts user to hash with all attributes' do
      user.save!
      hash = user.to_h
      expect(hash['id']).to eq(user.id)
      expect(hash['username']).to eq(username)
      expect(hash['password_digest']).to eq(user.password_digest)
      expect(hash['created_at']).to eq(user.created_at.iso8601)
      expect(hash['preferences']).to eq(preferences)
    end
  end

  describe '.from_h' do
    let(:user_hash) do
      {
        'username' => username,
        'password_digest' => BCrypt::Password.create(password).to_s,
        'preferences' => preferences
      }
    end

    it 'creates user instance from hash' do
      user = described_class.from_h(user_hash)
      user.save!
      expect(user.username).to eq(username)
      expect(user.password_digest).to eq(user_hash['password_digest'])
      expect(user.preferences).to eq(preferences)
    end

    it 'handles missing preferences' do
      user_hash.delete('preferences')
      user = described_class.from_h(user_hash)
      user.save!
      expect(user.preferences).to eq({})
    end
  end
end
