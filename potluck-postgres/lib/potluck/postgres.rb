# frozen_string_literal: true

require('potluck')
require('sequel')

module Potluck
  class Postgres < Service
    ROLE_NOT_FOUND_REGEX = /role .* does not exist/.freeze
    DATABASE_NOT_FOUND_REGEX = /database .* does not exist/.freeze

    STARTING_UP_STRING = 'the database system is starting up'
    STARTING_UP_TIMEOUT = 30

    CONNECTION_REFUSED_STRING = 'connection refused'
    CONNECTION_REFUSED_TIMEOUT = 3

    attr_reader(:database)

    def initialize(config, **args)
      super(**args)

      @config = config
    end

    def stop
      disconnect
      super
    end

    def connect
      (tries ||= 0) && (tries += 1)
      @database = Sequel.connect(@config, logger: @logger)
    rescue Sequel::DatabaseConnectionError => e
      if (dud = Sequel::DATABASES.last)
        dud.disconnect
        Sequel.synchronize { Sequel::DATABASES.delete(dud) }
      end

      message = e.message.downcase

      if message =~ ROLE_NOT_FOUND_REGEX && tries == 1
        create_database_role
        create_database
        retry
      elsif message =~ DATABASE_NOT_FOUND_REGEX && tries == 1
        create_database
        retry
      elsif message.include?(STARTING_UP_STRING) && tries < STARTING_UP_TIMEOUT
        sleep(1)
        retry
      elsif message.include?(CONNECTION_REFUSED_STRING) && tries < CONNECTION_REFUSED_TIMEOUT && manage?
        sleep(1)
        retry
      elsif message.include?(CONNECTION_REFUSED_STRING)
        abort("#{e.class}: #{e.message.strip}")
      else
        abort("#{e.class}: #{e.message.strip}\n  #{e.backtrace.join("\n  ")}")
      end
    end

    def disconnect
      @database&.disconnect
    end

    def create_database_role
      tmp_config = @config.dup
      tmp_config[:database] = 'postgres'
      tmp_config[:username] = ENV['USER']
      tmp_config[:password] = nil

      begin
        Sequel.connect(tmp_config, logger: @logger) do |database|
          database.execute("CREATE ROLE #{@config[:username]} WITH LOGIN CREATEDB REPLICATION PASSWORD "\
            "'#{@config[:password]}'")
        end
      rescue => e
        @logger.error("#{e.class}: #{e.message.strip}\n  #{e.backtrace.join("\n  ")}\n")
        abort("Could not create role '#{@config[:username]}'. Make sure database user '#{ENV['USER']}' "\
          'has permission to do so, or create it manually.')
      end
    end

    def create_database
      tmp_config = @config.dup
      tmp_config[:database] = 'postgres'

      begin
        Sequel.connect(tmp_config, logger: @logger) do |database|
          database.execute("CREATE DATABASE #{@config[:database]}")
        end
      rescue => e
        @logger.error("#{e.class}: #{e.message.strip}\n  #{e.backtrace.join("\n  ")}\n")
        abort("Could not create database '#{@config[:database]}'. Make sure database user "\
          "'#{@config[:username]}' has permission to do so, or create it manually.")
      end
    end

    def migrate(dir, steps = nil)
      return unless File.directory?(dir)

      Sequel.extension(:migration)

      # Suppress Sequel schema migration table queries.
      original_level = @logger.level
      @logger.level = Logger::WARN if @logger.level == Logger::INFO

      args = [Sequel::Model.db, dir, {allow_missing_migration_files: true}]
      migrator = Sequel::TimestampMigrator.new(*args)

      return if migrator.files.empty?

      if steps
        all = migrator.files.map { |f| File.basename(f) }
        applied = migrator.applied_migrations
        current = applied.last

        return if applied.empty? && steps <= 0

        index = [[0, (all.index(current) || -1) + steps].max, all.size].min
        file = all[index]

        args.last[:target] = migrator.send(:migration_version_from_file, file)
      end

      migrator = Sequel::TimestampMigrator.new(*args)
      @logger.level = original_level
      migrator.run
    ensure
      @logger.level = original_level if original_level
    end

    private

    def self.plist
      super(
        <<~EOS
          <key>ProgramArguments</key>
          <array>
            <string>/usr/local/opt/postgresql/bin/postgres</string>
            <string>-D</string>
            <string>/usr/local/var/postgres</string>
          </array>
          <key>WorkingDirectory</key>
          <string>/usr/local</string>
          <key>StandardOutPath</key>
          <string>/usr/local/var/log/postgres.log</string>
          <key>StandardErrorPath</key>
          <string>/usr/local/var/log/postgres.log</string>
        EOS
      )
    end
  end
end
