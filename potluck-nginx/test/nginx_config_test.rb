# frozen_string_literal: true

require_relative('test_helper')

class NginxConfigTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @config = Potluck::Nginx::Config.new
  end

  ##########################################################################################################
  ## Tests                                                                                                ##
  ##########################################################################################################

  test('constructor yields the instance being created if a block is given') do
    yielded_object = nil

    config = Potluck::Nginx::Config.new do |config|
      yielded_object = config
    end

    assert_equal(config, yielded_object)
  end

  test('uses 8080 as default HTTP port') do
    assert_equal(8080, @config.http_port)
  end

  test('allows HTTP port to be set') do
    @config.http_port = 8181

    assert_equal(8181, @config.http_port)
  end

  test('uses 4433 as default HTTPS port') do
    assert_equal(4433, @config.https_port)
  end

  test('allows HTTPS port to be set') do
    @config.http_port = 4321

    assert_equal(4321, @config.http_port)
  end
end
