# frozen_string_literal: true

require_relative('test_helper')

class PotluckTest < Minitest::Test
  include(TestHelper)

  test('provides a config object') do
    assert_kind_of(Potluck::Config, Potluck.config)
  end

  test('.configure yields the config object') do
    yielded_object = nil

    Potluck.configure do |config|
      yielded_object = config
    end

    assert_equal(Potluck.config, yielded_object)
  end
end
