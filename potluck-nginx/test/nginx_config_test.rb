# frozen_string_literal: true

require_relative('test_helper')

class NginxConfigTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Constructor                                                                                          ##
  ##########################################################################################################

  test('constructor accepts no block being given') do
    config = Potluck::Nginx::NginxConfig.new

    assert_equal('', config.to_s)
  end

  test('constructor calls a given block and passes self as an argument') do
    arg = nil

    config = Potluck::Nginx::NginxConfig.new do |c|
      arg = c
    end

    assert_equal(config, arg)
  end

  ##########################################################################################################
  ## Modification                                                                                         ##
  ##########################################################################################################

  test('#modify accepts no block being given') do
    config = Potluck::Nginx::NginxConfig.new
    config.modify

    assert_equal('', config.to_s)
  end

  test('#modify calls a given block and passes self as an argument') do
    arg = nil
    config = Potluck::Nginx::NginxConfig.new

    config.modify do |c|
      arg = c
    end

    assert_equal(config, arg)
  end

  test('#modify returns self') do
    config = Potluck::Nginx::NginxConfig.new
    return_value = config.modify

    assert_equal(config, return_value)
  end

  test('#<< appends hash content') do
    config = Potluck::Nginx::NginxConfig.new
    config << {
      'server' => {
        'access_log' => 'off',
        'add_header' => ['X-Content-Type-Options nosniff', 'X-Frame-Options DENY'],
        :'raw[0]' => 'return 404;',
      },
    }

    expected = <<~CONFIG
      server {
        access_log off;
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        return 404;
      }
    CONFIG

    assert_equal(expected, config.to_s)
  end

  test('#<< appends string content') do
    config = Potluck::Nginx::NginxConfig.new
    config << "charset UTF-8;\n"
    config << "access_log off;\n"

    expected = <<~CONFIG
      charset UTF-8;
      access_log off;
    CONFIG

    assert_equal(expected, config.to_s)
  end

  ##########################################################################################################
  ## DSL                                                                                                  ##
  ##########################################################################################################

  test('accepts arbitrary method calls and converts them to Nginx config directives') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset('UTF-8')
      c.access_log('off')
    end

    expected = <<~CONFIG
      charset UTF-8;
      access_log off;
    CONFIG

    assert_equal(expected, config.to_s)
  end

  test('accepts nested blocks and converts them to nested Nginx block directives') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.server do
        c.charset('UTF-8')
        c.access_log('off')

        c.location('/') do
          c.root('www/public')
          c.gzip_static('on')
        end
      end
    end

    expected = <<~CONFIG
      server {
        charset UTF-8;
        access_log off;
        location / {
          root www/public;
          gzip_static on;
        }
      }
    CONFIG

    assert_equal(expected, config.to_s)
  end

  test('ignores a directive with a nil value') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset(nil)
      c.access_log('off')
    end

    assert_equal("access_log off;\n", config.to_s)
  end

  test('ignores a directive with an empty string value') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset('')
      c.access_log('off')
    end

    assert_equal("access_log off;\n", config.to_s)
  end

  test('removes a directive when repeated with a nil value') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset('UTF-8')
      c.access_log('off')
      c.charset(nil)
    end

    assert_equal("access_log off;\n", config.to_s)
  end

  test('removes a directive when repeated with an empty string value') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset('UTF-8')
      c.access_log('off')
      c.charset('')
    end

    assert_equal("access_log off;\n", config.to_s)
  end

  test('treats the first arg as a key and overwrites any previous value when two or more args are given') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.add_header('X-Content-Type-Options', 'nosniff')
      c.add_header('X-Frame-Options', 'DENY')
      c.add_header('X-Frame-Options', 'SAMEORIGIN')
    end

    expected = <<~CONFIG
      add_header X-Content-Type-Options nosniff;
      add_header X-Frame-Options SAMEORIGIN;
    CONFIG

    assert_equal(expected, config.to_s)
  end

  test('appends a value for a repeated directive when soft: true') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.add_header('X-Content-Type-Options', 'nosniff')
      c.add_header('X-Frame-Options', 'DENY', soft: true)
    end

    expected = <<~CONFIG
      add_header X-Content-Type-Options nosniff;
      add_header X-Frame-Options DENY;
    CONFIG

    assert_equal(expected, config.to_s)
  end

  test('removes previously-added soft values for a repeated directive when :soft is not given') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.add_header('X-Content-Type-Options', 'nosniff', soft: true)
      c.add_header('X-Frame-Options', 'DENY')
    end

    assert_equal("add_header X-Frame-Options DENY;\n", config.to_s)
  end

  test('raises an error if a private method is called') do
    error = assert_raises(NoMethodError) do
      Potluck::Nginx::NginxConfig.new do |c|
        c.add_directive('access_log', 'off')
      end
    end

    assert_equal(
      "private method 'add_directive' called for an instance of Potluck::Nginx::NginxConfig",
      error.to_s
    )
  end

  ##########################################################################################################
  ## #dig                                                                                                 ##
  ##########################################################################################################

  test('#dig gets the values of a non-nested directive') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.charset('UTF-8')
      c.access_log('off')
    end

    assert_equal(['UTF-8'], config.dig('charset'))
  end

  test('#dig gets the values of a nested directive') do
    config = Potluck::Nginx::NginxConfig.new do |c|
      c.server do
        c.charset('UTF-8')
        c.access_log('off')

        c.location('/') do
          c.root('www/public')
          c.gzip_static('on')
        end
      end
    end

    assert_equal(['www/public'], config.dig('server', 0, 'location /', 0, 'root'))
  end

  ##########################################################################################################
  ## #respond_to?                                                                                         ##
  ##########################################################################################################

  test('#respond_to? returns true if the method is public') do
    config = Potluck::Nginx::NginxConfig.new

    assert(config.respond_to?(:modify))
  end

  test('#respond_to? returns false if the method is private') do
    config = Potluck::Nginx::NginxConfig.new

    refute(config.respond_to?(:add_directive))
  end

  test('#respond_to? returns false if the method is private and include_private = false') do
    config = Potluck::Nginx::NginxConfig.new

    refute(config.respond_to?(:add_directive, false))
  end

  test('#respond_to? returns true if the method is private and include_private = true') do
    config = Potluck::Nginx::NginxConfig.new

    assert(config.respond_to?(:add_directive, true))
  end

  test('#respond_to? returns true if the method is not implemented') do
    config = Potluck::Nginx::NginxConfig.new

    assert(config.respond_to?(:hello_world))
  end
end
