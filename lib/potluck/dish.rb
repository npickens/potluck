# frozen_string_literal: true

module Potluck
  class Dish
    SERVICE_PREFIX = 'potluck.npickens.'

    PLIST_XML = '<?xml version="1.0" encoding="UTF-8"?>'
    PLIST_DOCTYPE = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/Prope'\
      'rtyList-1.0.dtd">'

    LAUNCHCTL_ERROR_REGEX = /^-|\t[^0]\t/.freeze

    def initialize(logger: nil, is_local: nil)
      @logger = logger
      @is_local = is_local.nil? ? (IS_MACOS && ensure_launchctl! rescue false) : is_local
    end

    def ensure_launchctl!
      @@launchctl = `which launchctl` && $? == 0 unless defined?(@@launchctl)
      @@launchctl || raise("Cannot manage #{self.class.to_s.split('::').last}: launchctl not found")
    end

    def ensure_plist
      File.write(self.class.plist_path, self.class.plist)
    end

    def status
      return :inactive unless @is_local && ensure_launchctl!

      output = `launchctl list 2>&1 | grep #{SERVICE_PREFIX}#{self.class.service_name}`

      if $? != 0
        :inactive
      elsif output[LAUNCHCTL_ERROR_REGEX]
        :error
      else
        :active
      end
    end

    def start
      return unless @is_local && ensure_launchctl!

      ensure_plist

      case status
      when :error then stop
      when :active then return
      end

      run("launchctl bootstrap gui/#{Process.uid} #{self.class.plist_path}")
      wait { status == :inactive }

      raise("Could not start #{self.class.pretty_name}") if status != :active

      log("#{self.class.pretty_name} started")
    end

    def stop
      return unless @is_local && ensure_launchctl! && status != :inactive

      run("launchctl bootout gui/#{Process.uid}/#{self.class.launchctl_name}")
      wait { status != :inactive }

      raise("Could not stop #{self.class.pretty_name}") if status != :inactive

      log("#{self.class.pretty_name} stopped")
    end

    def restart
      return unless @is_local && ensure_launchctl!

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
end
