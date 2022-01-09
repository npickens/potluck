# frozen_string_literal: true

require('fileutils')

module Potluck
  ##
  # General error class used for errors encountered with a service.
  #
  class ServiceError < StandardError; end

  ##
  # A Ruby interface for configuring, controlling, and interacting with external processes. Serves as a
  # parent class for service-specific child classes.
  #
  class Service
    SERVICE_PREFIX = 'potluck.npickens.'
    LAUNCHCTL_ERROR_REGEX = /^-|\t[^0]\t/.freeze

    ##
    # Creates a new instance.
    #
    # * +logger+ - +Logger+ instance to use for outputting info and error messages (optional). Output will
    #   be sent to stdout and stderr if none is supplied.
    # * +manage+ - True if the service runs locally and should be managed by this process (default: true if
    #   launchctl is available and false otherwise).
    #
    def initialize(logger: nil, manage: self.class.launchctl?)
      @logger = logger
      @manage = !!manage
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

    ##
    # Returns true if the service is managed.
    #
    def manage?
      @manage
    end

    ##
    # Returns true if the service is managed via launchctl.
    #
    def manage_with_launchctl?
      @manage_with_launchctl
    end

    ##
    # Returns the status of the service:
    #
    # * +:active+ if the service is managed and running.
    # * +:inactive+ if the service is not managed or is not running.
    # * +:error+ if the service is managed and is in an error state.
    #
    def status
      return :inactive unless manage?

      output = `#{status_command}`

      if $? != 0
        :inactive
      elsif status_error_regex && output[status_error_regex]
        :error
      else
        :active
      end
    end

    ##
    # Starts the service if it's managed and is not active.
    #
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

    ##
    # Stops the service if it's managed and is active or in an error state.
    #
    def stop
      return unless manage? && status != :inactive

      self.class.write_plist if manage_with_launchctl?
      run(stop_command)
      wait { status != :inactive }

      raise(ServiceError, "Could not stop #{self.class.pretty_name}") if status != :inactive

      log("#{self.class.pretty_name} stopped")
    end

    ##
    # Restarts the service if it's managed by calling stop and then start.
    #
    def restart
      return unless manage?

      stop
      start
    end

    ##
    # Runs a command with the default shell. Raises an error if the command exits with a non-zero status.
    #
    # * +command+ - Command to run.
    # * +redirect_stderr+ - True if stderr should be redirected to stdout; otherwise stderr output will not
    #   be logged (default: true).
    #
    def run(command, redirect_stderr: true)
      output = `#{command}#{' 2>&1' if redirect_stderr}`
      status = $?

      if status != 0
        output.split("\n").each { |line| log(line, :error) }
        raise(ServiceError, "Command exited with status #{status.to_i}: #{command}")
      else
        output
      end
    end

    ##
    # Logs a message using the logger or stdout/stderr if no logger is configured.
    #
    # * +message+ - Message to log.
    # * +error+ - True if the message is an error (default: false).
    #
    def log(message, error = false)
      if @logger
        error ? @logger.error(message) : @logger.info(message)
      else
        error ? $stderr.puts(message) : $stdout.puts(message)
      end
    end

    ##
    # Human-friendly name of the service.
    #
    def self.pretty_name
      @pretty_name ||= self.to_s.split('::').last
    end

    ##
    # Computer-friendly name of the service.
    #
    def self.service_name
      @service_name ||= pretty_name.downcase
    end

    ##
    # Name for the launchctl service.
    #
    def self.launchctl_name
      "#{SERVICE_PREFIX}#{service_name}"
    end

    ##
    # Path to the launchctl plist file of the service.
    #
    def self.plist_path
      File.join(DIR, "#{launchctl_name}.plist")
    end

    ##
    # Content of the launchctl plist file.
    #
    def self.plist(content = '')
      <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        #{'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.'\
          '0.dtd">'}
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
      EOS
    end

    ##
    # Writes the service's launchctl plist file to disk.
    #
    def self.write_plist
      FileUtils.mkdir_p(File.dirname(plist_path))
      File.write(plist_path, plist)
    end

    ##
    # Returns true if launchctl is available.
    #
    def self.launchctl?
      defined?(@@launchctl) ? @@launchctl : (@@launchctl = `which launchctl 2>&1` && $? == 0)
    end

    ##
    # Checks if launchctl is available and raises an error if not.
    #
    def self.ensure_launchctl!
      launchctl? || raise(ServiceError, "Cannot manage #{pretty_name}: launchctl not found")
    end

    private

    ##
    # Command to get the status of the service.
    #
    def status_command
      @status_command || "launchctl list 2>&1 | grep #{SERVICE_PREFIX}#{self.class.service_name}"
    end

    ##
    # Regular expression to check the output of +#status_command+ against to determine if the service is in
    # an error state.
    #
    def status_error_regex
      @status_error_regex || LAUNCHCTL_ERROR_REGEX
    end

    ##
    # Command to start the service.
    #
    def start_command
      @start_command || "launchctl bootstrap gui/#{Process.uid} #{self.class.plist_path}"
    end

    ##
    # Command to stop the service.
    #
    def stop_command
      @stop_command || "launchctl bootout gui/#{Process.uid}/#{self.class.launchctl_name}"
    end

    ##
    # Calls the supplied block repeatedly until it returns false. Checks frequently at first and gradually
    # reduces down to one-second intervals.
    #
    # * +timeout+ - Maximum number of seconds to wait before timing out (default: 30).
    # * +block+ - Block to call until it returns false.
    #
    def wait(timeout = 30, &block)
      while block.call && timeout > 0
        reduce = [[(30 - timeout.to_i) / 5.0, 0.1].max, 1].min
        timeout -= reduce

        sleep(reduce)
      end
    end
  end
end
