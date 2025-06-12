# Rakefile
require 'bundler/setup' # Load Bundler
require 'rake'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Define a default task (e.g., run tests and rubocop)
task default: %i[test lint]

# RSpec task
RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = '--format documentation' # Nicer output
end

# RuboCop task
RuboCop::RakeTask.new(:lint) do |task|
  task.options = ['--auto-correct-all'] # Automatically fix issues
  # task.fail_on_error = true # Fail the Rake task if there are offenses
end

# Task to run all tests and check linting without auto-correction
desc 'Run all tests and linting'
task ci: %i[test lint]

# Task to generate SimpleCov report
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task['test'].execute
  puts 'Coverage report generated in coverage/index.html'
end

# Add other custom tasks as needed, e.g.:
# task :clean do
#   sh 'rm -rf data/*.json log/*.log' # Example cleanup
# end
