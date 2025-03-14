# frozen_string_literal: true

require('English')
require('fileutils')

module Potluck
  # Public: General error class used for errors encountered with a service.
  class ServiceError < StandardError; end

  # Public: A Ruby interface for configuring, controlling, and interacting with external processes. Serves
  # as a parent class for service-specific child classes.
  class Service
    SERVICE_PREFIX = 'potluck.npickens.'
    LAUNCHCTL_ERROR_REGEX = /^-|\t[^0]\t/

    # Public: Get the human-friendly name of the service.
    #
    # Returns the String name.
    def self.pretty_name
      @pretty_name ||= to_s.split('::').last
    end

    # Public: Get the computer-friendly name of the service.
    #
    # Returns the String name.
    def self.service_name
      @service_name ||= pretty_name.downcase
    end

    # Public: Get the name for the launchctl service.
    #
    # Returns the String name.
    def self.launchctl_name
      "#{SERVICE_PREFIX}#{service_name}"
    end

    # Public: Get the path to the launchctl plist file of the service.
    #
    # Returns the String path.
    def self.plist_path
      File.join(Potluck.config.dir, "#{launchctl_name}.plist")
    end

    # Public: Get the content of the launchctl plist file.
    #
    # Returns the String content.
    def self.plist(content = '')
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        #{'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1' \
          '.0.dtd">'}
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>#{launchctl_name}</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          #{content.gsub(/^/, '  ').strip}
        </dict>
        </plist>
      XML
    end

    # Public: Write the service's launchctl plist file to disk.
    #
    # Returns nothing.
    def self.write_plist
      FileUtils.mkdir_p(File.dirname(plist_path))
      File.write(plist_path, plist)
    end

    # Public: Check if launchctl is available.
    #
    # Returns the boolean result.
    def self.launchctl?
      return @@launchctl if defined?(@@launchctl)

      `which launchctl 2>&1`

      @@launchctl = $CHILD_STATUS.success?
    end

    # Public: Raise an error if launchctl is not available.
    #
    # Returns true if launchctl is available.
    # Raises ServiceError if launchctl is not available.
    def self.ensure_launchctl!
      launchctl? || raise(ServiceError, "Cannot manage #{pretty_name}: launchctl not found")
    end

    # Public: Create a new instance.
    #
    # logger: - Logger instance to use in place of sending output to stdin and stderr.
    # manage: - Boolean specifying if the service runs locally and should be managed by this process
    #           (defaults to whether or not launchctl is available); or a configuration Hash:
    #
    #           status:             - String command for fetching the status of the service.
    #           status_error_regex: - Regexp that determines if the service is in an error state.
    #           start:              - String command for starting the service.
    #           stop:               - String command for stopping the service.
    def initialize(logger: nil, manage: self.class.launchctl?)
      @logger = logger
      @manage = manage
      @manage_with_launchctl = false

      if manage.kind_of?(Hash)
        @status_command = manage[:status]
        @status_error_regex = manage[:status_error_regex]
        @start_command = manage[:start]
        @stop_command = manage[:stop]
      elsif manage
        @manage_with_launchctl = true
        self.class.ensure_launchctl!
      end
    end

    # Public: Check if the service is managed by this process.
    #
    # Returns the boolean result.
    def manage?
      @manage
    end

    # Public: Check if the service is managed by launchctl.
    #
    # Returns the boolean result.
    def manage_with_launchctl?
      @manage_with_launchctl
    end

    # Public: Get the status of the service.
    #
    # Returns :active if the service is managed and running, :inactive if the service is not managed or is
    # not running, or :error if the service is managed and is in an error state.
    def status
      return :inactive unless manage?

      output = `#{status_command}`

      if !$CHILD_STATUS.success?
        :inactive
      elsif status_error_regex && output[status_error_regex]
        :error
      else
        :active
      end
    end

    # Public: Start the service if it's managed and is not active.
    #
    # Returns nothing.
    def start
      return unless manage?

      case status
      when :error then stop
      when :active then return
      end

      self.class.write_plist if manage_with_launchctl?
      run(start_command)
      wait { status == :inactive }

      raise(ServiceError, "Could not start #{self.class.pretty_name}") if status != :active

      log("#{self.class.pretty_name} started")
    end

    # Public: Stop the service if it's managed and is active or in an error state.
    #
    # Returns nothing.
    # Raises ServiceError if the service could not be stopped.
    def stop
      return unless manage? && status != :inactive

      self.class.write_plist if manage_with_launchctl?
      run(stop_command)
      wait { status != :inactive }

      raise(ServiceError, "Could not stop #{self.class.pretty_name}") if status != :inactive

      log("#{self.class.pretty_name} stopped")
    end

    # Public: Restart the service if it's managed.
    #
    # Returns nothing.
    def restart
      return unless manage?

      stop
      start
    end

    # Public: Run a command with the default shell.
    #
    # command         - String command to run.
    # capture_stderr: - Boolean specifying if stderr should be redirected to stdout (if false, stderr output
    #                   will not be logged).
    #
    # Returns the String output of the command.
    # Raises ServiceError if the command exited with a non-zero status.
    def run(command, capture_stderr: true)
      output = `#{command}#{' 2>&1' if capture_stderr}`
      status = $CHILD_STATUS

      if status.success?
        output
      else
        output.split("\n").each { |line| log(line, :error) }
        raise(ServiceError, "Command exited with status #{status.exitstatus}: #{command}")
      end
    end

    # Public: Log a message using the logger or stdout/stderr if no logger is configured.
    #
    # message - String message to log.
    # error   - Boolean specifying if the message is an error.
    #
    # Returns nothing.
    def log(message, error = false)
      if @logger
        error ? @logger.error(message) : @logger.info(message)
      else
        error ? $stderr.puts(message) : $stdout.puts(message)
      end
    end

    private

    # Internal: Get the command for fetching the status of the service.
    #
    # Returns the String command.
    def status_command
      @status_command || "launchctl list 2>&1 | grep #{SERVICE_PREFIX}#{self.class.service_name}"
    end

    # Internal: Get the regex used to determine if the service is in an error state (by matching the output
    # of the status command against it).
    #
    # Returns the Regexp.
    def status_error_regex
      @status_error_regex || LAUNCHCTL_ERROR_REGEX
    end

    # Internal: Get the command for starting the service.
    #
    # Returns the String command.
    def start_command
      @start_command || "launchctl bootstrap gui/#{Process.uid} #{self.class.plist_path}"
    end

    # Internal: Get the command for stopping the service.
    #
    # Returns the String command.
    def stop_command
      @stop_command || "launchctl bootout gui/#{Process.uid}/#{self.class.launchctl_name}"
    end

    # Internal: Call the supplied block repeatedly until it returns false. Checks frequently at first and
    # gradually reduces down to one-second intervals.
    #
    # timeout - Integer maximum number of seconds to wait before timing out.
    # block   - Proc to call until it returns false.
    #
    # Returns nothing.
    def wait(timeout = 30, &block)
      while block.call && timeout > 0
        reduce = ((30 - timeout.to_i) / 5.0).clamp(0.1, 1)
        timeout -= reduce

        sleep(reduce)
      end
    end
  end
end
