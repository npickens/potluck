# frozen_string_literal: true

require_relative('test_helper')

class NginxTest < Minitest::Test
  include(TestHelper)

  test('provides a config object') do
    assert_kind_of(Potluck::Nginx::Config, Potluck::Nginx.config)
  end

  test('.configure yields the config object') do
    yielded_object = nil

    Potluck::Nginx.configure do |config|
      yielded_object = config
    end

    assert_equal(Potluck::Nginx.config, yielded_object)
  end

  test('.plist returns plist content using configured Homebrew prefix') do
    Potluck.configure do |config|
      config.homebrew_prefix = '/hello/world'
    end

    plist = Potluck::Nginx.plist

    assert_includes(plist, '<string>/hello/world/opt/nginx/bin/nginx</string>')
    assert_includes(plist, '<string>/hello/world/var/log/nginx/access.log</string>')
    assert_includes(plist, '<string>/hello/world/var/log/nginx/error.log</string>')
  ensure
    Potluck.config = Potluck::Config.new
  end

  # More tests coming...
end
