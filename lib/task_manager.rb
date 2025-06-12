# core components
require_relative 'task_manager/core/errors'
require_relative 'task_manager/core/helpers'

# configuration
require_relative 'task_manager/config/application_config'

# models
require_relative 'task_manager/models/user'
require_relative 'task_manager/models/task'

# persistence
require_relative 'task_manager/persistence/file_store'

# services
require_relative 'task_manager/services/user_service'
require_relative 'task_manager/services/task_service'

# filtering strategies
require_relative 'task_manager/strategies/filtering/base_filter_strategy'
require_relative 'task_manager/strategies/filtering/tag_filter_strategy'
require_relative 'task_manager/strategies/filtering/due_date_filter_strategy'

# sorting strategies
require_relative 'task_manager/strategies/sorting/base_sort_strategy'
require_relative 'task_manager/strategies/sorting/due_date_sort_strategy'
require_relative 'task_manager/strategies/sorting/priority_sort_strategy'

# notifications
require_relative 'task_manager/notifications/notifier'
require_relative 'task_manager/notifications/email_sender'

# user interface
require_relative 'task_manager/cli'

# top-level namespace
module TaskManager
  VERSION = "0.1.0".freeze
end