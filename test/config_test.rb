# frozen_string_literal: true

require_relative('test_helper')

class ConfigTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @config = Potluck::Config.new
  end

  ##########################################################################################################
  ## Tests                                                                                                ##
  ##########################################################################################################

  test('constructor yields the instance being created if a block is given') do
    yielded_object = nil

    config = Potluck::Config.new do |c|
      yielded_object = c
    end

    assert_equal(config, yielded_object)
  end

  test('uses ~/.potluck as default dir') do
    assert_equal(File.expand_path('~/.potluck'), @config.dir)
  end

  test('allows dir to be set') do
    @config.dir = '/hello/world'

    assert_equal('/hello/world', @config.dir)
  end

  test('uses value of $HOMEBREW_PREFIX environment variable as Homebrew prefix if it is set') do
    ENV['HOMEBREW_PREFIX'] = '/hello/world'

    assert_equal('/hello/world', @config.homebrew_prefix)
  end

  test('uses /usr/local as Homebrew prefix if $HOMEBREW_PREFIX environment variable is not set') do
    ENV['HOMEBREW_PREFIX'] = nil

    assert_equal('/usr/local', @config.homebrew_prefix)
  end

  test('allows homebrew_prefix to be set') do
    @config.homebrew_prefix = '/hello/world'

    assert_equal('/hello/world', @config.homebrew_prefix)
  end
end
