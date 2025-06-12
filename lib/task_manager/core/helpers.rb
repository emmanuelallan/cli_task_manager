module TaskManager
  module Core
    # helper methods for common operations across the application
    module Helpers
      # converts string to date object
      # @param date_string [String, Date, nil] input string or date
      # @return [Date, nil] parsed date or nil if invalid
      def self.parse_date(date_string)
        return date_string if date_string.is_a?(Date)
        return nil if date_string.nil? || date_string.strip.empty?

        begin
          Date.parse(date_string)
        rescue ArgumentError
          nil
        end
      end

      # converts string to time object
      # @param time_string [String, Time, nil] input string or time
      # @return [Time, nil] parsed time or nil if invalid
      def self.parse_time(time_string)
        return time_string if time_string.is_a?(Time)
        return nil if time_string.nil? || time_string.strip.empty?

        begin
          Time.parse(time_string)
        rescue ArgumentError
          nil
        end
      end

      # formats date to string
      # @param date_obj [Date, nil] date to format
      # @return [String, nil] formatted date (YYYY-MM-DD) or nil
      def self.format_date(date_obj)
        date_obj&.iso8601
      end

      # formats time to string
      # @param time_obj [Time, nil] time to format
      # @return [String, nil] formatted time (ISO 8601) or nil
      def self.format_time(time_obj)
        time_obj&.iso8601
      end

      # cleans up string input
      # @param text [String, nil] input text
      # @return [String, nil] cleaned string
      def self.sanitize_string(text)
        text&.strip
      end

      # NOTE: add more utility methods here as needed
      # - email validation
      # - id formatting
      # - display formatting
    end
  end
end
