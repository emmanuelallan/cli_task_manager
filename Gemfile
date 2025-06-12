# Gemfile
source 'https://rubygems.org'

# Core CLI Gems
gem 'thor', '~> 1.2' # For robust CLI command parsing and subcommands
gem 'colorize', '~> 0.8' # For colorful console output
gem 'tty-prompt', '~> 0.23' # For interactive CLI prompts (optional, but enhances UX)

# Data Persistence & Security
gem 'json' # Ruby's built-in JSON library (good to list for clarity)
gem 'yaml' # Ruby's built-in YAML library (good to list for clarity)
gem 'bcrypt', '~> 3.1' # For secure password hashing

# Date & Time (built-in, no gem needed, but useful context)
# require 'date'
# require 'time'

# For Data Export/Import (built-in)
# require 'csv'

# Logging
gem 'logger' # Ruby's built-in Logger class (good to list for clarity)

# Development & Testing Gems
group :development, :test do
  gem 'rspec', '~> 3.10' # Testing framework
  gem 'rubocop', '~> 1.25' # Code linter and formatter
  gem 'faker', '~> 2.18' # For generating fake data in tests
  gem 'simplecov', '~> 0.21', require: false # For code coverage reporting
end

# Optional: Advanced features
# gem 'rufus-scheduler' # For background task reminders
# gem 'terminal-notifier' # For macOS desktop notifications (platform specific)
# gem 'tty-spinner' # For progress indicators