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

require 'rspec'
require 'active_record'
require 'fileutils'
require 'bcrypt'

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Additional configuration
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"

  config.order = :random
  Kernel.srand config.seed

  # Clean up test data after each spec
  config.after(:each) do
    # Clean up any test database files
    test_db_path = File.join(ENV['TMPDIR'] || '/tmp', 'task_manager_test', 'task_manager.db')
    FileUtils.rm_rf(File.dirname(test_db_path)) if File.exist?(test_db_path)
  end
end