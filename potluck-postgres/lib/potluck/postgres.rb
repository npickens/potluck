# frozen_string_literal: true

require('potluck')
require('sequel')

module Potluck
  ##
  # Error class used to wrap errors encountered while connecting to or setting up a database.
  #
  class PostgresError < ServiceError
    attr_reader(:wrapped_error)

    ##
    # Creates a new instance.
    #
    # * +message+ - Error message.
    # * +wrapped_error+ - Original error that was rescued and is being wrapped by this one (optional).
    #
    def initialize(message, wrapped_error = nil)
      super(message)

      @wrapped_error = wrapped_error
    end
  end

  ##
  # A Ruby interface for controlling and connecting to Postgres. Uses
  # [Sequel](https://github.com/jeremyevans/sequel) to connect and perform automatic role and database
  # creation, as well as for utility methods such as database schema migration.
  #
  class Postgres < Service
    ROLE_NOT_FOUND_REGEX = /role .* does not exist/.freeze
    DATABASE_NOT_FOUND_REGEX = /database .* does not exist/.freeze

    STARTING_UP_STRING = 'the database system is starting up'
    STARTING_UP_TIMEOUT = 30

    CONNECTION_REFUSED_STRING = 'connection refused'
    CONNECTION_REFUSED_TIMEOUT = 3

    attr_reader(:database)

    ##
    # Creates a new instance.
    #
    # * +config+ - Configuration hash to pass to <tt>Sequel.connect</tt>.
    # * +args+ - Arguments to pass to Potluck::Service.new (optional).
    #
    def initialize(config, **args)
      super(**args)

      @config = config
    end

    ##
    # Disconnects and stops the Postgres process.
    #
    def stop
      disconnect
      super
    end

    ##
    # Connects to the configured Postgres database.
    #
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
        raise(PostgresError.new(e.message.strip, e))
      else
        raise
      end
    end

    ##
    # Disconnects from the database if a connection was made.
    #
    def disconnect
      @database&.disconnect
    end

    ##
    # Runs database migrations by way of Sequel's migration extension. Migration files must use the
    # timestamp naming strategy as opposed to integers.
    #
    # * +dir+ - Directory where migration files are located.
    # * +steps+ - Number of steps forward or backward to migrate from the current migration, otherwise will
    #   migrate to latest (optional).
    #
    def migrate(dir, steps = nil)
      return unless File.directory?(dir)

      Sequel.extension(:migration)

      # Suppress Sequel schema migration table queries.
      original_level = @logger.level
      @logger.level = Logger::WARN if @logger.level == Logger::INFO

      args = [@database, dir, {allow_missing_migration_files: true}]
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

    ##
    # Content of the launchctl plist file.
    #
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

    private

    ##
    # Attempts to connect to the 'postgres' database as the system user with no password and create the
    # configured role. Useful in development.
    #
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
        raise(PostgresError.new("Database role #{@config[:username].inspect} could not be created using "\
          "system user #{tmp_config[:username].inspect}. Please create the role manually.", e))
      end
    end

    ##
    # Attempts to connect to the 'postgres' database with the configured user and password and create the
    # configured database. Useful in development.
    #
    def create_database
      tmp_config = @config.dup
      tmp_config[:database] = 'postgres'

      begin
        Sequel.connect(tmp_config, logger: @logger) do |database|
          database.execute("CREATE DATABASE #{@config[:database]}")
        end
      rescue => e
        raise(PostgresError.new("Database #{@config[:database].inspect} could not be created by "\
          "connecting to system database #{tmp_config[:database].inspect}. Please create the database "\
          'manually.', e))
      end
    end
  end
end
