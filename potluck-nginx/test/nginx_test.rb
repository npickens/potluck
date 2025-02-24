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

  # More tests coming...
end
