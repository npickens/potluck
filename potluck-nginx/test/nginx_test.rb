# frozen_string_literal: true

require_relative('test_helper')

class NginxTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Configuration                                                                                        ##
  ##########################################################################################################

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

  ##########################################################################################################
  ## Plist                                                                                                ##
  ##########################################################################################################

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

  ##########################################################################################################
  ## URL Normalization - Host                                                                             ##
  ##########################################################################################################

  test('does not map hosts when one_host: false and :www is not given') do
    map = {
      'default' => '$host',
    }

    assert_equal(map, config_entry(nginx(one_host: false), 'map $host $host_normalized'))
  end

  test('maps each host to its non-www version when one_host: false and www: false') do
    map = {
      'default' => '$host',
      'www.hello.world' => 'hello.world',
      'www.hi.there' => 'hi.there',
    }

    assert_equal(map, config_entry(nginx(one_host: false, www: false), 'map $host $host_normalized'))
  end

  test('maps each host to its www version when one_host: false and www: true') do
    map = {
      'default' => '$host',
      'hello.world' => 'www.hello.world',
      'hi.there' => 'www.hi.there',
    }

    assert_equal(map, config_entry(nginx(one_host: false, www: true), 'map $host $host_normalized'))
  end

  test('maps each host to equivalent version of first host when one_host: true and :www is not given') do
    map = {
      'default' => '$host',
      'hi.there' => 'hello.world',
      'www.hi.there' => 'www.hello.world',
    }

    assert_equal(map, config_entry(nginx(one_host: true), 'map $host $host_normalized'))
  end

  test('maps each host to non-www version of first host when one_host: true and www: false') do
    map = {
      'default' => '$host',
      'www.hello.world' => 'hello.world',
      'www.hi.there' => 'hello.world',
      'hi.there' => 'hello.world',
    }

    assert_equal(map, config_entry(nginx(one_host: true, www: false), 'map $host $host_normalized'))
  end

  test('maps each host to www version of first host when one_host: true and www: true') do
    map = {
      'default' => '$host',
      'hello.world' => 'www.hello.world',
      'www.hi.there' => 'www.hello.world',
      'hi.there' => 'www.hello.world',
    }

    assert_equal(map, config_entry(nginx(one_host: true, www: true), 'map $host $host_normalized'))
  end

  ##########################################################################################################
  ## URL Normalization - Multiple Slashes                                                                 ##
  ##########################################################################################################

  test('does not reduce multiple slashes in URIs when :multiple_slashes is not given') do
    assert_equal('off', config_entry(nginx, 'server', 'merge_slashes'))
  end

  test('does not reduce multiple slashes in URIs when multiple_slashes: true') do
    assert_equal('off', config_entry(nginx(multiple_slashes: true), 'server', 'merge_slashes'))
  end

  test('reduces multiple slashes to a single slash in URIs when multiple_slashes: false') do
    assert_equal('on', config_entry(nginx(multiple_slashes: false), 'server', 'merge_slashes'))
  end

  ##########################################################################################################
  ## URL Normalization - Trailing Slash                                                                   ##
  ##########################################################################################################

  test('does not normalize trailing slash(es) in URIs when :trailing_slash is not given') do
    map = {
      'default' => '$uri',
    }

    assert_equal(map, config_entry(nginx, 'map $uri $uri_normalized'))
  end

  test('strips trailing slash(es) in URIs when trailing_slash: false') do
    map = {
      'default' => '$uri',
      '~^(.*/[^/.]+)/+$' => '$1',
    }

    assert_equal(map, config_entry(nginx(trailing_slash: false), 'map $uri $uri_normalized'))
  end

  test('ensures trailing slash in URIs when trailing_slash: true') do
    map = {
      'default' => '$uri',
      '~^(.*/[^/.]+)$' => '$1/',
    }

    assert_equal(map, config_entry(nginx(trailing_slash: true), 'map $uri $uri_normalized'))
  end

  ##########################################################################################################
  ## URL Normalization - Question Marks                                                                   ##
  ##########################################################################################################

  test('does not normalize question marks in URIs when :multiple_question_marks and ' \
       ':trailing_question_mark are not given') do
    map = {
      'default' => '$q$args',
    }

    assert_equal(map, config_entry(nginx, 'map $q$args $args_normalized'))
  end

  test('strips trailing question mark(s) in URIs when :multiple_question_marks is not given and ' \
       'trailing_question_mark: false') do
    map = {
      'default' => '$q$args',
      '~^(\\?+)$' => "''",
    }

    assert_equal(map, config_entry(nginx(trailing_question_mark: false), 'map $q$args $args_normalized'))
  end

  test('ensures trailing question mark when :multiple_question_marks is not given and ' \
       'trailing_question_mark: true') do
    map = {
      'default' => '$q$args',
      "''" => '?',
    }

    assert_equal(map, config_entry(nginx(trailing_question_mark: true), 'map $q$args $args_normalized'))
  end

  test('reduces multiple question marks in URIs when multiple_question_marks: false and ' \
       ':trailing_question_mark is not given') do
    map = {
      'default' => '$q$args',
      '~^\\?+([^\\?].*)$' => '?$1',
      '~^(\\?+)$' => '?',
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: false), 'map $q$args $args_normalized'))
  end

  test('reduces multiple question marks and strips trailing question mark(s) in URIs when ' \
       ':multiple_question_marks: false and trailing_question_mark: false') do
    map = {
      'default' => '$q$args',
      '~^\\?+([^\\?].*)$' => '?$1',
      '~^(\\?+)$' => "''",
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: false, trailing_question_mark: false),
      'map $q$args $args_normalized'))
  end

  test('reduces multiple question marks and ensures trailing question mark when multiple_question_marks: ' \
       'false and trailing_question_mark: true') do
    map = {
      'default' => '$q$args',
      '~^\\?+([^\\?].*)$' => '?$1',
      '~^(\\?+)$' => '?',
      "''" => '?',
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: false, trailing_question_mark: true),
      'map $q$args $args_normalized'))
  end

  test('does not normalize question marks in URIs when multiple_question_marks: true and ' \
       ':trailing_question_mark is not given') do
    map = {
      'default' => '$q$args',
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: true), 'map $q$args $args_normalized'))
  end

  test('strips trailing question mark(s) in URIs when :multiple_question_marks: true and ' \
       'trailing_question_mark: false') do
    map = {
      'default' => '$q$args',
      '~^(\\?+)$' => "''",
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: true, trailing_question_mark: false),
      'map $q$args $args_normalized'))
  end

  test('does not reduce multiple question marks and ensures trailing question mark when ' \
       'multiple_question_marks: true and trailing_question_mark: true') do
    map = {
      'default' => '$q$args',
      "''" => '?',
    }

    assert_equal(map, config_entry(nginx(multiple_question_marks: true, trailing_question_mark: true),
      'map $q$args $args_normalized'))
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def nginx(*args, **kwargs)
    Potluck::Nginx.new(%w[hello.world hi.there], 1234, **kwargs)
  end

  def config_entry(nginx, *keys)
    entry = nginx.send(:config)

    keys.each do |key|
      entry = entry[key] or break
    end

    entry.kind_of?(Hash) ? entry.compact : entry
  end
end
