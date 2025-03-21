# frozen_string_literal: true

require('potluck')
require('sequel')
require_relative('postgres/version')

module Potluck
  # Public: Error class used to wrap errors encountered while connecting to or setting up a database.
  class PostgresError < ServiceError
    attr_reader(:wrapped_error)

    # Public: Create a new instance.
    #
    # message       - String error message.
    # wrapped_error - Original Exception that was rescued and is being wrapped by this one.
    def initialize(message, wrapped_error = nil)
      super(message)

      @wrapped_error = wrapped_error
    end
  end

  # Public: A Ruby interface for controlling and connecting to Postgres. Uses the Sequel gem to connect and
  # perform automatic role and database creation, as well as for utility methods such as database schema
  # migration.
  class Postgres < Service
    ROLE_NOT_FOUND_REGEX = /role .* does not exist/
    DATABASE_NOT_FOUND_REGEX = /database .* does not exist/

    STARTING_UP_STRING = 'the database system is starting up'
    STARTING_UP_TRIES = 30

    CONNECTION_REFUSED_STRING = 'connection refused'
    CONNECTION_REFUSED_TRIES = 3

    attr_reader(:database)

    # Public: Get the content of the launchctl plist file.
    #
    # Returns the String content.
    def self.plist
      dir = postgres_dir

      super(
        <<~XML
          <key>EnvironmentVariables</key>
          <dict>
            <key>LC_ALL</key>
            <string>C</string>
          </dict>
          <key>ProgramArguments</key>
          <array>
            <string>#{Potluck.config.homebrew_prefix}/opt/#{dir}/bin/postgres</string>
            <string>-D</string>
            <string>#{Potluck.config.homebrew_prefix}/var/#{dir}</string>
          </array>
          <key>WorkingDirectory</key>
          <string>#{Potluck.config.homebrew_prefix}</string>
          <key>StandardOutPath</key>
          <string>#{Potluck.config.homebrew_prefix}/var/log/#{dir}.log</string>
          <key>StandardErrorPath</key>
          <string>#{Potluck.config.homebrew_prefix}/var/log/#{dir}.log</string>
        XML
      )
    end

    # Public: Get the directory of the latest Homebrew-installed Postgres version.
    #
    # Returns the String path.
    # Raises PostgresError if no Homebrew Postgres installation is found.
    def self.postgres_dir
      versions = Dir[File.join(Potluck.config.homebrew_prefix, 'opt', 'postgresql@*')].sort_by do |path|
        path.split('@').last.to_f
      end

      if versions.empty?
        raise(PostgresError, 'No Postgres installation found (try running `brew install postgresql@X`)')
      end

      File.basename(versions.last)
    end

    # Public: Create a new instance.
    #
    # config - Configuration Hash to pass to Sequel.connect.
    # kwargs - Hash of keyword arguments to pass to Service.new.
    def initialize(config, **kwargs)
      super(**kwargs)

      @config = config
    end

    # Public: Disconnect and stop the Postgres process.
    #
    # Returns nothing.
    def stop
      disconnect
      super
    end

    # Public: Connect to the configured Postgres database.
    #
    # Returns nothing.
    # Raises Sequel::DatabaseConnectionError if connecting fails.
    # Raises PostgresError if role creation was attempted and failed.
    # Raises PostgresError if database creation was attempted and failed.
    # Raises PostgresError if permission grant was attempted and failed.
    def connect
      role_created = false
      database_created = false

      begin
        (tries ||= 0) && (tries += 1)
        @database = Sequel.connect(@config, logger: @logger)
      rescue Sequel::DatabaseConnectionError => e
        if (dud = Sequel::DATABASES.last)
          dud.disconnect
          Sequel.synchronize { Sequel::DATABASES.delete(dud) }
        end

        message = e.message.downcase

        if message =~ ROLE_NOT_FOUND_REGEX && !role_created && manage?
          role_created = true
          create_role
          retry
        elsif message =~ DATABASE_NOT_FOUND_REGEX && !database_created && manage?
          database_created = true
          create_database
          retry
        elsif message.include?(STARTING_UP_STRING) && tries < STARTING_UP_TRIES
          sleep(1)
          retry
        elsif message.include?(CONNECTION_REFUSED_STRING) && tries < CONNECTION_REFUSED_TRIES
          sleep(1)
          retry
        else
          raise
        end
      end

      # Only grant permissions if the database already existed but the role did not. Automatic database
      # creation (via #create_database) is performed as the configured role, which means explicit permission
      # granting is not necessary.
      grant_permissions if role_created && !database_created
    end

    # Public: Disconnect from the database if a connection was made.
    #
    # Returns nothing.
    def disconnect
      @database&.disconnect
    end

    # Deprecated: Run database migrations by way of Sequel's migration extension. Migration files must use
    # the timestamp naming strategy as opposed to integers.
    #
    # dir   - String directory where migration files are located.
    # steps - Integer number of steps forward or backward to migrate from the current migration (if omitted,
    #         will migrate forward to latest migration).
    #
    # Returns nothing.
    def migrate(dir, steps = nil)
      location = caller_locations(1, 1).first

      warn("#{location.path}:#{location.lineno}: #{self.class.name}#migrate is deprecated and will be " \
        "removed soon. Please use Sequel's migration extension directly instead.")

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

        index = [[0, (all.index(current) || -1) + steps].max, all.size - 1].min
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

    # Internal: Attempt to connect to the 'postgres' database as the system user with no password and create
    # the configured role. Useful in development environments.
    #
    # Returns nothing.
    # Raises PostgresError if the role could not be created.
    def create_role
      tmp_config = admin_database_config
      tmp_config[:database] = 'postgres'

      begin
        Sequel.connect(tmp_config, logger: @logger) do |database|
          database.execute("CREATE ROLE \"#{@config[:username]}\" WITH LOGIN CREATEDB REPLICATION" \
            "#{" PASSWORD '#{@config[:password]}'" if @config[:password]}")
        end
      rescue => e
        raise(PostgresError.new("Failed to create database role #{@config[:username].inspect} by " \
          "connecting to database #{tmp_config[:database].inspect} as role " \
          "#{tmp_config[:username].inspect}. Please create the role manually.", e))
      end
    end

    # Internal: Attempt to connect to the 'postgres' database with the configured user and password and
    # create the configured database. Useful in development environments.
    #
    # Returns nothing.
    # Raises PostgresError if the database could not be created.
    def create_database
      tmp_config = @config.dup
      tmp_config[:database] = 'postgres'

      begin
        Sequel.connect(tmp_config, logger: @logger) do |database|
          database.execute("CREATE DATABASE \"#{@config[:database]}\"")
        end
      rescue => e
        raise(PostgresError.new("Failed to create database #{@config[:database].inspect} by connecting " \
          "to database #{tmp_config[:database].inspect} as role #{tmp_config[:username].inspect}. " \
          'Please create the database manually.', e))
      end
    end

    # Internal: Grant appropriate permissions for the configured database role. Useful in development
    # environments.
    #
    # Returns nothing.
    # Raises PostgresError if permissions could not be granted.
    def grant_permissions
      tmp_config = admin_database_config

      begin
        Sequel.connect(tmp_config, logger: @logger) do |db|
          db.execute("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"#{@config[:username]}\"")
          db.execute("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"#{@config[:username]}\"")
          db.execute("ALTER DEFAULT PRIVILEGES FOR ROLE \"#{@config[:username]}\" IN SCHEMA public GRANT " \
            "ALL PRIVILEGES ON TABLES TO \"#{@config[:username]}\"")
        end
      rescue => e
        raise(PostgresError.new('Failed to grant database permissions for role ' \
          "#{@config[:username].inspect} by connecting as role #{tmp_config[:username].inspect}. Please " \
          'grant appropriate permissions manually.', e))
      end
    end

    # Internal: Return a configuration hash for connecting to Postgres to perform administrative tasks
    # (role and database creation). Uses the system user as the username and no password. Useful in
    # development environments
    #
    # Returns the configuration Hash.
    def admin_database_config
      config = @config.dup
      config[:username] = ENV.fetch('USER')
      config[:password] = nil

      config
    end
  end
end
