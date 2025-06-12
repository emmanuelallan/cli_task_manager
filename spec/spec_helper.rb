# spec/spec_helper.rb
require 'bundler/setup'
require 'simplecov' # For code coverage, must be at the very top
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/bin/"
  add_filter "/config/"
  add_filter "/data/"
end if ENV['COVERAGE']

# Load your application's main entry point
require_relative '../lib/task_manager'

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Additional configuration
  config.mock_with :rspec do |mocks|
    # You can configure your mocks here, e.g., to verify doubles
    mocks.verify_partial_doubles = true
  end

  # Clean up test data after each spec (important for file-based persistence)
  config.after(:each) do
    # You'll need to define methods or helper classes to manage test data files
    # For example:
    # File.delete('data/test_tasks.json') if File.exist?('data/test_tasks.json')
    # File.delete('data/test_users.json') if File.exist?('data/test_users.json')
    # Or, mock File.open/read/write in tests to not hit the filesystem at all.
  end
end