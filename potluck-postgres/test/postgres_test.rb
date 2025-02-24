# frozen_string_literal: true

require_relative('test_helper')

class PostgresTest < Minitest::Test
  include(TestHelper)

  test('.plist returns plist content using configured Homebrew prefix') do
    Potluck.configure do |config|
      config.homebrew_prefix = '/hello/world'
    end

    plist = Potluck::Postgres.stub(:postgres_dir, 'postgresql@15') do
      Potluck::Postgres.plist
    end

    assert_includes(plist, '<string>/hello/world/opt/postgresql@15/bin/postgres</string>')
    assert_includes(plist, '<string>/hello/world/var/postgresql@15</string>')
    assert_includes(plist, '<string>/hello/world</string>')
    assert_includes(plist, '<string>/hello/world/var/log/postgresql@15.log</string>')
    assert_includes(plist, '<string>/hello/world/var/log/postgresql@15.log</string>')
  ensure
    Potluck.config = Potluck::Config.new
  end

  test('#connect retries when connection is refused and then raises original error') do
    postgres = Potluck::Postgres.new({})

    tries = 0
    error = nil
    error_message = 'connection to [...] failed: Connection refused'
    sequel_connect = lambda do |*, **|
      tries += 1
      raise(Sequel::DatabaseConnectionError, error_message)
    end

    postgres.stub(:sleep, nil) do
      Sequel.stub(:connect, sequel_connect) do
        error = assert_raises(Sequel::DatabaseConnectionError) do
          postgres.connect
        end
      end
    end

    assert_equal(error_message, error.message)
    assert_equal(3, tries)
  end

  # More tests coming...
end
