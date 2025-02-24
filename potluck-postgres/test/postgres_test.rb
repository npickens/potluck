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

  # More tests coming...
end
