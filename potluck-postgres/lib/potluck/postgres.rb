# frozen_string_literal: true

require('potluck')

module Potluck
  class Postgres < Dish
    attr_reader(:database)

    def initialize(config, **args)
      super(**args)

      @config = config
    end

    def connect
      (tries ||= 0) && (tries += 1)
      @database = Sequel.connect(@config, logger: @logger)
    rescue Sequel::DatabaseConnectionError => e
      if (dud = Sequel::DATABASES.last)
        dud.disconnect
        Sequel.synchronize { Sequel::DATABASES.delete(dud) }
      end

      if e.message =~ /role .* does not exist/ && tries == 1
        create_database_role
        create_database
        retry
      elsif e.message =~ /database .* does not exist/ && tries == 1
        create_database
        retry
      elsif (@is_local && tries < 3) && (e.message.include?('could not connect') ||
          e.message.include?('the database system is starting up'))
        sleep(1)
        retry
      elsif e.message.include?('could not connect')
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
      @logger.level = Logger::WARN

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
