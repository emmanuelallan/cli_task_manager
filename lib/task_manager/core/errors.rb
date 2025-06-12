module TaskManager
  # base error class for all task manager exceptions
  class TaskManagerError < StandardError
    def initialize(message = "An unknown Task Manager error occurred.")
      super(message)
    end
  end

  # handles auth failures (invalid login)
  class AuthenticationError < TaskManagerError
    def initialize(message = "Authentication failed. Invalid username or password.")
      super(message)
    end
  end

  # handles missing user lookups
  class UserNotFoundError < TaskManagerError
    def initialize(message = "User not found.")
      super(message)
    end
  end

  # handles duplicate username registration
  class UsernameAlreadyExistsError < TaskManagerError
    def initialize(message = "Username already exists.")
      super(message)
    end
  end

  # handles missing task lookups
  class TaskNotFoundError < TaskManagerError
    def initialize(message = "Task not found.")
      super(message)
    end
  end

  # handles malformed user input or data
  class InvalidInputError < TaskManagerError
    def initialize(message = "Invalid input provided.")
      super(message)
    end
  end

  # handles file operation failures
  class FileError < TaskManagerError
    def initialize(message = "A file operation error occurred.")
      super(message)
    end
  end

  # note: additional file error types can be added as needed:
  # - FileLoadError for read operations
  # - FileSaveError for write operations
end