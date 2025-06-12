require 'spec_helper'
require_relative '../../../../lib/task_manager/services/user_service'
require_relative '../../../../lib/task_manager/models/user'

RSpec.describe TaskManager::Services::UserService do
  let(:service) { described_class.new }
  let(:username) { 'testuser' }
  let(:password) { 'secure_password123' }
  let(:user_id) { 'test-user-123' }

  before(:all) do
    # Ensure database connection is established
    TaskManager::Persistence::DatabaseStore.establish_connection
  end

  before(:each) do
    # Clean up any existing test data
    TaskManager::Models::User.delete_all
  end

  describe '#register_user' do
    it 'creates a new user with valid credentials' do
      user = service.register_user(username, password)
      expect(user).to be_a(TaskManager::Models::User)
      expect(user.username).to eq(username)
      expect(user.authenticate(password)).to be true
    end

    it 'raises UsernameAlreadyExistsError for duplicate username' do
      service.register_user(username, password)
      expect {
        service.register_user(username, 'another_password')
      }.to raise_error(TaskManager::UsernameAlreadyExistsError)
    end

    it 'raises InvalidInputError for invalid user data' do
      expect {
        service.register_user('', password)
      }.to raise_error(TaskManager::InvalidInputError)
    end
  end

  describe '#authenticate_user' do
    before do
      service.register_user(username, password)
    end

    it 'returns user for valid credentials' do
      user = service.authenticate_user(username, password)
      expect(user).to be_a(TaskManager::Models::User)
      expect(user.username).to eq(username)
    end

    it 'raises UserNotFoundError for non-existent username' do
      expect {
        service.authenticate_user('nonexistent', password)
      }.to raise_error(TaskManager::UserNotFoundError)
    end

    it 'raises AuthenticationError for incorrect password' do
      expect {
        service.authenticate_user(username, 'wrong_password')
      }.to raise_error(TaskManager::AuthenticationError)
    end
  end

  describe '#find_user_by_id' do
    let!(:user) do
      service.register_user(username, password)
    end

    it 'returns user for existing id' do
      found_user = service.find_user_by_id(user.id)
      expect(found_user).to be_a(TaskManager::Models::User)
      expect(found_user.id).to eq(user.id)
    end

    it 'returns nil for non-existent id' do
      expect(service.find_user_by_id('nonexistent')).to be_nil
    end
  end

  describe '#find_user_by_username' do
    let!(:user) do
      service.register_user(username, password)
    end

    it 'returns user for existing username' do
      found_user = service.find_user_by_username(username)
      expect(found_user).to be_a(TaskManager::Models::User)
      expect(found_user.username).to eq(username)
    end

    it 'returns nil for non-existent username' do
      expect(service.find_user_by_username('nonexistent')).to be_nil
    end

    it 'is case insensitive' do
      found_user = service.find_user_by_username(username.upcase)
      expect(found_user).to be_a(TaskManager::Models::User)
      expect(found_user.username).to eq(username)
    end
  end

  describe '#get_all_users' do
    before do
      service.register_user('user1', 'pass1')
      service.register_user('user2', 'pass2')
    end

    it 'returns all users' do
      users = service.get_all_users
      expect(users).to be_an(Array)
      expect(users.length).to eq(2)
      expect(users.map(&:username)).to match_array(['user1', 'user2'])
    end
  end
end
