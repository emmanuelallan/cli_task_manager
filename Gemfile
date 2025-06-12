# Gemfile
source 'https://rubygems.org'

# Core CLI Gems
gem 'thor' # For robust CLI command parsing and subcommands
gem 'colorize' # For colorful console output
gem 'tty-prompt' # For interactive CLI prompts (optional, but enhances UX)

# Data Persistence & Security
gem 'json' # Ruby's built-in JSON library (good to list for clarity)
gem 'psych' # Ruby's built-in YAML library (good to list for clarity)
gem 'bcrypt' # For secure password hashing

# Date & Time (built-in, no gem needed, but useful context)
# require 'date'
# require 'time'

# For Data Export/Import (built-in)
require 'csv'

# data storage
gem 'sqlite3'
gem 'activerecord'

# Logging
gem 'logger' # Ruby's built-in Logger class (good to list for clarity)

# System Notifications
# gem 'terminal-notifier', '~> 2.0' # For macOS desktop notifications (uncomment if on macOS)
gem 'libnotify', '~> 0.9' # For Linux desktop notifications

# Development & Testing Gems
group :development, :test do
  gem 'rspec', '~> 3.10' # Testing framework
  gem 'rubocop', '~> 1.25' # Code linter and formatter
  gem 'faker', '~> 2.18' # For generating fake data in tests
  gem 'simplecov', '~> 0.21', require: false # For code coverage reporting
  gem 'rake' # For running Rake tasks
end

# Optional: Advanced features
# gem 'rufus-scheduler' # For background task reminders
# gem 'tty-spinner' # For progress indicators

# For UUID generation (already part of standard library, but good to be explicit if needed)
# gem 'securerandom' # Often not needed in Gemfile as it's default in Ruby

# For Singleton pattern (already part of standard library)
# gem 'singleton' # Not needed in Gemfile for standard library modules

# For Observer pattern (already part of standard library)
gem 'observer' # Not needed in Gemfile for standard library modules