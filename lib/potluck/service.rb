# frozen_string_literal: true

module Potluck
  class Service
    SERVICE_PREFIX = 'potluck.npickens.'

    PLIST_XML = '<?xml version="1.0" encoding="UTF-8"?>'
    PLIST_DOCTYPE = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/Prope'\
      'rtyList-1.0.dtd">'

    LAUNCHCTL_ERROR_REGEX = /^-|\t[^0]\t/.freeze

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

      # DEPRECATED. Use `manage` instead.
      @is_local = is_local.nil? ? (IS_MACOS && ensure_launchctl! rescue false) : is_local

      unless is_local_omitted
        warn("#{self.class}#initialize `is_local` parameter is deprecated and will be removed soon (use "\
          '`manage` instead)')
      end
    end

    def manage?
      @manage
    end

    def launchctl?
      defined?(@@launchctl) ? @@launchctl : (@@launchctl = `which launchctl 2>&1` && $? == 0)
    end

    def ensure_launchctl!
      launchctl? || raise("Cannot manage #{self.class.to_s.split('::').last}: launchctl not found")
    end

    def status_command
      @status_command || "launchctl list 2>&1 | grep #{SERVICE_PREFIX}#{self.class.service_name}"
    end

    def status_error_regex
      @status_error_regex || LAUNCHCTL_ERROR_REGEX
    end

    def start_command
      @start_command || "launchctl bootstrap gui/#{Process.uid} #{self.class.plist_path}"
    end

    def stop_command
      @stop_command || "launchctl bootout gui/#{Process.uid}/#{self.class.launchctl_name}"
    end

    def ensure_plist
      File.write(self.class.plist_path, self.class.plist)
    end

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

    def stop
      return unless manage? && status != :inactive

      run(stop_command)
      wait { status != :inactive }

      raise("Could not stop #{self.class.pretty_name}") if status != :inactive

      log("#{self.class.pretty_name} stopped")
    end

    def restart
      return unless manage?

      stop
      start
    end

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

    def log(message, error = false)
      if @logger
        error ? @logger.error(message) : @logger.info(message)
      else
        error ? $stderr.puts(message) : $stdout.puts(message)
      end
    end

    private

    def wait(timeout = 30, &block)
      while block.call && timeout > 0
        reduce = [[(30 - timeout.to_i) / 5.0, 0.1].max, 1].min
        timeout -= reduce

        sleep(reduce)
      end
    end

    def self.pretty_name
      @pretty_name ||= self.to_s.split('::').last
    end

    def self.service_name
      @service_name ||= pretty_name.downcase
    end

    def self.launchctl_name
      "#{SERVICE_PREFIX}#{service_name}"
    end

    def self.plist_path
      File.join(DIR, "#{launchctl_name}.plist")
    end

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

  Dish = Service.clone

  class Dish
    def self.inherited(subclass)
      warn("Potluck::Dish has been renamed to Potluck::Service. Please update #{subclass} to inherit from "\
        'Potluck::Service instead of Potluck::Dish.')
    end
  end
end
