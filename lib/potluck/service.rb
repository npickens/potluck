# frozen_string_literal: true

module Potluck
  ##
  # A Ruby interface for controlling, configuring, and interacting with external processes. Serves as a
  # parent class for service-specific child classes.
  #
  class Service
    SERVICE_PREFIX = 'potluck.npickens.'

    PLIST_XML = '<?xml version="1.0" encoding="UTF-8"?>'
    PLIST_DOCTYPE = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/Prope'\
      'rtyList-1.0.dtd">'

    LAUNCHCTL_ERROR_REGEX = /^-|\t[^0]\t/.freeze

    ##
    # Creates a new instance.
    #
    # * +logger+ - +Logger+ instance to use for outputting info and error messages (optional). Output will
    #   be sent to stdout and stderr if none is supplied.
    # * +manage+ - True if the service runs locally and should be managed by this process (default: true if
    #   launchctl is available and false otherwise).
    # * +is_local+ - DEPRECATED. True if the service runs locally (use +manage+ instead).
    #
    def initialize(logger: nil, manage: launchctl?, is_local: (is_local_omitted = true; nil))
      @logger = logger
      @manage = !!manage

      if manage.kind_of?(Hash)
        @status_command = manage[:status]
        @status_error_regex = manage[:status_error_regex]
        @start_command = manage[:start]
        @stop_command = manage[:stop]
      elsif manage
        ensure_launchctl!
      end

      # DEPRECATED. Use +manage+ instead.
      @is_local = is_local.nil? ? (IS_MACOS && ensure_launchctl! rescue false) : is_local

      unless is_local_omitted
        warn("#{self.class}#initialize `is_local` parameter is deprecated and will be removed soon (use "\
          '`manage` instead)')
      end
    end

    ##
    # Returns true if the service is managed.
    #
    def manage?
      @manage
    end

    ##
    # Returns true if launchctl is available.
    #
    def launchctl?
      defined?(@@launchctl) ? @@launchctl : (@@launchctl = `which launchctl 2>&1` && $? == 0)
    end

    ##
    # Checks if launchctl is available and raises an error if not.
    #
    def ensure_launchctl!
      launchctl? || raise("Cannot manage #{self.class.to_s.split('::').last}: launchctl not found")
    end

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
    # Writes the service's launchctl plist file to disk.
    #
    def ensure_plist
      File.write(self.class.plist_path, self.class.plist)
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

      ensure_plist unless @start_command

      case status
      when :error then stop
      when :active then return
      end

      run(start_command)
      wait { status == :inactive }

      raise("Could not start #{self.class.pretty_name}") if status != :active

      log("#{self.class.pretty_name} started")
    end

    ##
    # Stops the service if it's managed and is active or in an error state.
    #
    def stop
      return unless manage? && status != :inactive

      run(stop_command)
      wait { status != :inactive }

      raise("Could not stop #{self.class.pretty_name}") if status != :inactive

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
        raise("Command exited with status #{status.to_i}: #{command}")
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

    private

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
    def self.plist(content)
      <<~EOS
        #{PLIST_XML}
        #{PLIST_DOCTYPE}
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
  end

  ##
  # DEPRECATED. Old name of Potluck::Service class.
  #
  Dish = Service.clone

  # :nodoc: all
  class Dish
    def self.inherited(subclass)
      warn("Potluck::Dish has been renamed to Potluck::Service. Please update #{subclass} to inherit from "\
        'Potluck::Service instead of Potluck::Dish.')
    end
  end
end
