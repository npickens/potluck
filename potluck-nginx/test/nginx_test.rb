# frozen_string_literal: true

require_relative('test_helper')

class NginxTest < Minitest::Test
  include(TestHelper)

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
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: false))
  end

  test('maps each host to its non-www version when one_host: false and www: false') do
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
        www.hello.world hello.world;
        www.hi.there hi.there;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: false, www: false))
  end

  test('maps each host to its www version when one_host: false and www: true') do
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
        hello.world www.hello.world;
        hi.there www.hi.there;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: false, www: true))
  end

  test('maps each host to equivalent version of first host when one_host: true and :www is not given') do
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
        www.hi.there www.hello.world;
        hi.there hello.world;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: true))
  end

  test('maps each host to non-www version of first host when one_host: true and www: false') do
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
        www.hello.world hello.world;
        www.hi.there hello.world;
        hi.there hello.world;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: true, www: false))
  end

  test('maps each host to www version of first host when one_host: true and www: true') do
    map = <<~CONFIG
      map $host $hello_world_host {
        default $host;
        hello.world www.hello.world;
        www.hi.there www.hello.world;
        hi.there www.hello.world;
      }
    CONFIG

    assert_equal(map, find_in_config(map, one_host: true, www: true))
  end

  ##########################################################################################################
  ## URL Normalization - Multiple Slashes                                                                 ##
  ##########################################################################################################

  test('does not reduce multiple slashes in URIs when :multiple_slashes is not given') do
    assert_equal('off', dig_in_config('server', 0, 'merge_slashes', 0))
  end

  test('does not reduce multiple slashes in URIs when multiple_slashes: true') do
    assert_equal('off', dig_in_config('server', 0, 'merge_slashes', 0, multiple_slashes: true))
  end

  test('reduces multiple slashes to a single slash in URIs when multiple_slashes: false') do
    assert_equal('on', dig_in_config('server', 0, 'merge_slashes', 0, multiple_slashes: false))
  end

  ##########################################################################################################
  ## URL Normalization - Trailing Slash                                                                   ##
  ##########################################################################################################

  test('does not normalize trailing slash(es) in URIs when :trailing_slash is not given') do
    map = <<~CONFIG
      map $uri $hello_world_uri {
        default $uri;
      }
    CONFIG

    assert_equal(map, find_in_config(map))
  end

  test('strips trailing slash(es) in URIs when trailing_slash: false') do
    map = <<~CONFIG
      map $uri $hello_world_uri {
        default $uri;
        ~^(.*/[^/.]+)/+$ $1;
      }
    CONFIG

    assert_equal(map, find_in_config(map, trailing_slash: false))
  end

  test('ensures trailing slash in URIs when trailing_slash: true') do
    map = <<~CONFIG
      map $uri $hello_world_uri {
        default $uri;
        ~^(.*/[^/.]+)$ $1/;
      }
    CONFIG

    assert_equal(map, find_in_config(map, trailing_slash: true))
  end

  ##########################################################################################################
  ## URL Normalization - Question Marks                                                                   ##
  ##########################################################################################################

  test('does not normalize question marks in URIs when :multiple_question_marks and ' \
       ':trailing_question_mark are not given') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
      }
    CONFIG

    assert_equal(map, find_in_config('map $hello_world_q$query_string $hello_world_query'))
  end

  test('strips trailing question mark(s) in URIs when :multiple_question_marks is not given and ' \
       'trailing_question_mark: false') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        ~^(\\?+)$ '';
      }
    CONFIG

    assert_equal(map, find_in_config(map, trailing_question_mark: false))
  end

  test('ensures trailing question mark when :multiple_question_marks is not given and ' \
       'trailing_question_mark: true') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        '' ?;
      }
    CONFIG

    assert_equal(map, find_in_config(map, trailing_question_mark: true))
  end

  test('reduces multiple question marks in URIs when multiple_question_marks: false and ' \
       ':trailing_question_mark is not given') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        ~^\\?+([^\\?].*)$ ?$1;
        ~^(\\?+)$ ?;
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: false))
  end

  test('reduces multiple question marks and strips trailing question mark(s) in URIs when ' \
       ':multiple_question_marks: false and trailing_question_mark: false') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        ~^\\?+([^\\?].*)$ ?$1;
        ~^(\\?+)$ '';
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: false, trailing_question_mark: false))
  end

  test('reduces multiple question marks and ensures trailing question mark when multiple_question_marks: ' \
       'false and trailing_question_mark: true') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        ~^\\?+([^\\?].*)$ ?$1;
        ~^(\\?+)$ ?;
        '' ?;
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: false, trailing_question_mark: true))
  end

  test('does not normalize question marks in URIs when multiple_question_marks: true and ' \
       ':trailing_question_mark is not given') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: true))
  end

  test('strips trailing question mark(s) in URIs when :multiple_question_marks: true and ' \
       'trailing_question_mark: false') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        ~^(\\?+)$ '';
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: true, trailing_question_mark: false))
  end

  test('does not reduce multiple question marks and ensures trailing question mark when ' \
       'multiple_question_marks: true and trailing_question_mark: true') do
    map = <<~CONFIG
      map $hello_world_q$query_string $hello_world_query {
        default $hello_world_q$query_string;
        '' ?;
      }
    CONFIG

    assert_equal(map, find_in_config(map, multiple_question_marks: true, trailing_question_mark: true))
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def find_in_config(directive, **nginx_kwargs)
    config = nginx(**nginx_kwargs).config
    key = directive.split("\n").first.chomp(' {')
    hash = config.instance_variable_get(:@config).select { |k| k == key }

    config.send(:to_nginx_config, hash)
  end

  def dig_in_config(*keys, **nginx_kwargs)
    nginx(**nginx_kwargs).config.dig(*keys)
  end

  def nginx(**kwargs)
    Potluck::Nginx.new(%w[hello.world hi.there], 1234, **kwargs)
  end
end
