# frozen_string_literal: true

module Potluck
  # Configuration settings for Nginx service.
  class Nginx < Service
    class Config
      DEFAULT_HTTP_PORT = 8080
      DEFAULT_HTTPS_PORT = 4433

      attr_writer(:http_port, :https_port)

      # Public: Create a new instance.
      #
      # Yields the instance being created.
      #
      # Examples
      #
      #   Config.new do |config|
      #     config.http_port = 8181
      #     config.https_port = 4321
      #   end
      def initialize
        yield(self) if block_given?
      end

      # Public: Get the HTTP port setting.
      #
      # Returns the Integer value.
      def http_port
        @http_port || DEFAULT_HTTP_PORT
      end

      # Public: Get the HTTPS port setting.
      #
      # Returns the Integer value.
      def https_port
        @https_port || DEFAULT_HTTPS_PORT
      end
    end
  end
end
