# frozen_string_literal: true

require('fileutils')
require('potluck')
require_relative('nginx/nginx_config')
require_relative('nginx/version')

module Potluck
  # Public: A Ruby interface for configuring and controlling Nginx.
  #
  # Each instance of this class manages a separate Nginx configuration file, which is loaded and unloaded
  # from the base Nginx configuration when #start and #stop are called, respectively. Any number of Ruby
  # processes can thus each manage their own Nginx configuration and control whether or not it is active
  # without interfering with any other instances or non-Ruby processes leveraging Nginx.
  #
  # A standard set of Nginx config directives are generated automatically, and a flexible DSL can be used to
  # modify and/or embellish them.
  #
  # Examples
  #
  #   Nginx.new('hello.world', 1234) do |c|
  #     c.server do
  #       c.access_log('/path/to/access.log')
  #       c.gzip('off')
  #
  #       c.location('/hello') do
  #         c.try_files('world.html')
  #       end
  #     end
  #   end
  class Nginx < Service
    CONFIG_NAME_ACTIVE = 'nginx.conf'
    CONFIG_NAME_INACTIVE = 'nginx-stopped.conf'
    ACTIVE_CONFIG_PATTERN = File.join(Potluck.config.dir, '*', CONFIG_NAME_ACTIVE).freeze

    TEST_CONFIG_REGEX = /nginx: configuration file (?<config>.+) test (failed|is successful)/
    INCLUDE_REGEX = /^ *include +#{Regexp.escape(ACTIVE_CONFIG_PATTERN)} *;/

    NON_LAUNCHCTL_COMMANDS = {
      status: 'ps aux | grep \'[n]ginx: master process\'',
      start: 'nginx',
      stop: 'nginx -s stop',
    }.freeze

    DEFAULT_HTTP_PORT = 8080
    DEFAULT_HTTPS_PORT = 4433

    SSL_CERT_DAYS = 365
    SSL_CERT_RENEW_DAYS = 14

    # Public: Get the content of the launchctl plist file.
    #
    # Returns the String content.
    def self.plist
      super(
        <<~EOS
          <key>ProgramArguments</key>
          <array>
            <string>#{Potluck.config.homebrew_prefix}/opt/nginx/bin/nginx</string>
            <string>-g</string>
            <string>daemon off;</string>
          </array>
          <key>StandardOutPath</key>
          <string>#{Potluck.config.homebrew_prefix}/var/log/nginx/access.log</string>
          <key>StandardErrorPath</key>
          <string>#{Potluck.config.homebrew_prefix}/var/log/nginx/error.log</string>
        EOS
      )
    end

    # Internal: Print a warning with the file and line number of a deprecated call.
    #
    # message - String deprecation message.
    #
    # Returns nothing.
    def self.deprecated(message)
      location = caller_locations(2, 1).first

      warn("#{location.path}:#{location.lineno}: #{message}")
    end

    # Public: Create a new instance.
    #
    # hosts                    - String or Array of String hosts.
    # port                     - Integer port that the upstream (Ruby web server) is running on.
    # subdomains:              - String or Array of String fully qualified subdomains (e.g. 'sub.hello.com',
    #                            not 'sub.').
    # ssl:                     - Boolean indicating if SSL should be used. If true and SSL files are not
    #                            configured, a self-signed certificate will be generated.
    # one_host:                - Boolean specifying if URLs should be normalized to the first item in hosts.
    # www:                     - Boolean specifying if URLs should be normalized to include 'www.' (true),
    #                            exclude it (false), or allow either (nil).
    # multiple_slashes:        - Boolean specifying if URLs should be normalized to reduce multiple
    #                            slashes in a row to a single one (false) or leave them alone (true or nil).
    # multiple_question_marks: - Boolean specifying if URLs should be normalized to reduce multiple question
    #                            marks in a row to a single one (false) or leave them alone (true or nil).
    # trailing_slash:          - Boolean specifying if URLs should be normalized to include a trailing slash
    #                            (true), exclude it (false), or allow either (nil).
    # trailing_question_mark:  - Boolean specifying if URLs should be normalized to include a trailing
    #                            question mark (true), exclude it (false), or allow either (nil).
    # config:                  - Deprecated: Nginx server block configuration Hash. Use a block instead.
    # ensure_host_entries:     - Boolean specifying if hosts should be added to system /etc/hosts file as
    #                            mappings to localhost.
    # kwargs                   - Hash of keyword arguments to pass to Service.new.
    # block                    - Block for making modifications to the Nginx config. See NginxConfig#modify.
    def initialize(hosts, port, subdomains: nil, ssl: false, one_host: false, www: nil,
                   multiple_slashes: nil, multiple_question_marks: nil, trailing_slash: nil,
                   trailing_question_mark: nil, config: nil, ensure_host_entries: false, **kwargs, &block)
      if kwargs[:manage] && !kwargs[:manage].kind_of?(Hash) && !self.class.launchctl?
        kwargs[:manage] = NON_LAUNCHCTL_COMMANDS
      end

      super(**kwargs)

      if config
        self.class.deprecated("Passing config: {...} to #{self.class.name}.new is deprecated: use a " \
          'block instead')

        @deprecated_additional_config = config
      end

      if ssl.kind_of?(Hash)
        self.class.deprecated("Passing ssl: {...} to #{self.class.name}.new is deprecated: pass ssl: " \
          'true and use a block to configure SSL instead')

        @deprecated_ssl_crt_file = ssl[:crt_file]
        @deprecated_ssl_key_file = ssl[:key_file]
        @deprecated_ssl_dhparam_file = ssl[:dhparam_file]
        @deprecated_ssl_config = ssl[:config]

        all_given = @deprecated_ssl_crt_file && @deprecated_ssl_key_file && @deprecated_ssl_dhparam_file
        none_given = !@deprecated_ssl_crt_file && !@deprecated_ssl_key_file && !@deprecated_ssl_dhparam_file

        unless all_given || none_given
          raise(ArgumentError, 'Must supply values for all SSL files or none: crt_file, key_file, ' \
            'dhparam_file')
        end
      end

      @hosts = Array(hosts).map { |h| h.sub(/^www\./, '') }.uniq
      @subdomains = Array(subdomains)
      @host = @hosts.first || @subdomains.first
      @server_names = @hosts + @hosts.map { |h| "www.#{h}" } + @subdomains
      @var_prefix = "$#{@host.downcase.gsub(/[^a-z0-9]/, '_')}"
      @port = port
      @ssl = !!ssl
      @one_host = !!one_host
      @www = www
      @multiple_slashes = multiple_slashes
      @multiple_question_marks = multiple_question_marks
      @trailing_slash = trailing_slash
      @trailing_question_mark = trailing_question_mark
      @ensure_host_entries = ensure_host_entries

      @dir = File.join(Potluck.config.dir, @host).freeze
      @config_file_active = File.join(@dir, CONFIG_NAME_ACTIVE).freeze
      @config_file_inactive = File.join(@dir, CONFIG_NAME_INACTIVE).freeze

      @default_ssl_certificate = File.join(@dir, "#{@host}.crt")
      @default_ssl_certificate_key = File.join(@dir, "#{@host}.key")
      @default_ssl_dhparam = File.join(@dir, 'dhparam.pem')

      FileUtils.mkdir_p(@dir)

      @config = NginxConfig.new

      add_upstream_config
      add_host_map_config
      add_port_map_config
      add_path_map_config
      add_query_map_config
      add_server_config

      config(&block) if block
    end

    # Public: Ensure this instance's configuration file is active and start Nginx. If Nginx is already
    # running, send a reload signal to the process after activating the configuration file. Does nothing if
    # Nginx is not managed.
    #
    # Returns nothing.
    def start
      return unless manage?

      ensure_ssl_files
      ensure_host_entries
      ensure_include

      write_config
      activate_config

      run('nginx -t')

      status == :active ? reload : super
    end

    # Public: Ensure this instance's configuration file is inactive and optionally stop Nginx. Does nothing
    # if Nginx is not managed.
    #
    # hard - Boolean specifying if the Nginx process should be stopped (true) or this instance's
    #        configuration file simply inactivated (false).
    #
    # Returns nothing.
    def stop(hard = false)
      return unless manage?

      deactivate_config

      hard || status != :active ? super() : reload
    end

    # Public: Reload Nginx. Does nothing if Nginx is not managed.
    #
    # Returns nothing.
    def reload
      return unless manage?

      run('nginx -s reload')
    end

    # Public: Get or modify the config.
    #
    # block - Block for making modifications. See NginxConfig#modify.
    #
    # Returns the NginxConfig instance.
    def config(&block)
      block ? @config.modify(&block) : @config
    end

    private

    # Internal: Add upstream directive to the config.
    #
    # Returns nothing.
    def add_upstream_config
      config.upstream(@host) do |c|
        c.server("127.0.0.1:#{@port}")
      end
    end

    # Internal: Add map directive for URL host normalization to the config.
    #
    # Returns nothing.
    def add_host_map_config
      host_map = @hosts.each.with_object({}) do |host, map|
        www_key = "www.#{host}"
        www_value = "#{'www.' unless @www == false}#{@one_host ? @host : host}"

        non_www_key = host
        non_www_value = "#{'www.' if @www}#{@one_host ? @host : host}"

        map[www_key] = www_value unless www_key == www_value
        map[non_www_key] = non_www_value unless non_www_key == non_www_value
      end

      config.map("$host #{@var_prefix}_host") do |c|
        c << {
          'default' => '$host',
          **host_map,
        }
      end
    end

    # Internal: Add map directives for URL port normalization to the config.
    #
    # Returns nothing.
    def add_port_map_config
      normalized_port = @ssl ? DEFAULT_HTTPS_PORT : DEFAULT_HTTP_PORT

      config.map("$http_host #{@var_prefix}_request_port") do |c|
        c << {
          'default' => "''",
          '~(:[0-9]+)$' => '$1',
        }
      end

      config.map("$http_host #{@var_prefix}_port") do |c|
        c << {
          'default' => "''",
          '~:[0-9]+$' => ":#{normalized_port}",
        }
      end

      config.map("$http_host #{@var_prefix}_x_forwarded_port") do |c|
        c << {
          'default' => normalized_port,
          '~:([0-9]+)$' => '$1',
        }
      end
    end

    # Internal: Add map directive for URL path normalization to the config.
    #
    # Returns nothing.
    def add_path_map_config
      config.map("$uri #{@var_prefix}_uri") do |c|
        c << {
          'default' => '$uri',
          '~^(.*/[^/.]+)/+$' => ('$1' if @trailing_slash == false),
          '~^(.*/[^/.]+)$' => ('$1/' if @trailing_slash),
        }
      end
    end

    # Internal: Add map directives for URL query string normalization to the config.
    #
    # Returns nothing.
    def add_query_map_config
      config.map("$request_uri #{@var_prefix}_q") do |c|
        c << {
          'default' => "''",
          '~\\?' => '?',
        }
      end

      config.map("#{@var_prefix}_q$query_string #{@var_prefix}_query") do |c|
        c << {
          'default' => "#{@var_prefix}_q$query_string",
          '~^\\?+([^\\?].*)$' => ('?$1' if @multiple_question_marks == false),
          '~^(\\?+)$' =>
            if @trailing_question_mark == false
              "''"
            elsif @multiple_question_marks == false
              '?'
            end,
          "''" => ('?' if @trailing_question_mark),
        }
      end
    end

    # Internal: Add base/default server definition to the config.
    #
    # Returns nothing.
    def add_server_config
      config.server do |c|
        c.server_name(@server_names)

        c.listen(DEFAULT_HTTP_PORT, soft: true)
        c.listen("[::]:#{DEFAULT_HTTP_PORT}", soft: true)

        if @ssl
          c.listen(DEFAULT_HTTPS_PORT, 'ssl', soft: true)
          c.listen("[::]:#{DEFAULT_HTTPS_PORT}", 'ssl', soft: true)
          c.http2('on', soft: true)

          if @deprecated_ssl_crt_file
            c.ssl_certificate(@deprecated_ssl_crt_file)
            c.ssl_certificate_key(@deprecated_ssl_key_file)
            c.ssl_dhparam(@deprecated_ssl_dhparam_file)
          else
            c.ssl_certificate(@default_ssl_certificate, soft: true)
            c.ssl_certificate_key(@default_ssl_certificate_key, soft: true)
            c.ssl_dhparam(@default_ssl_dhparam, soft: true)
          end

          c.ssl_ciphers('ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-' \
            'GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-' \
            'POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384', soft: true)
          c.ssl_prefer_server_ciphers('off', soft: true)
          c.ssl_protocols('TLSv1.2 TLSv1.3', soft: true)
          c.ssl_session_cache('shared:SSL:10m', soft: true)
          c.ssl_session_tickets('off', soft: true)
          c.ssl_session_timeout('1d', soft: true)
          c.ssl_stapling('on', soft: true)
          c.ssl_stapling_verify('on', soft: true)

          add_deprecated_config(@deprecated_ssl_config)
        end

        c.charset('UTF-8', soft: true)

        c.access_log(File.join(@dir, 'nginx-access.log'), soft: true)
        c.error_log(File.join(@dir, 'nginx-error.log'), soft: true)

        c.merge_slashes(@multiple_slashes == false ? 'on' : 'off', soft: true)

        c.gzip('on', soft: true)
        c.gzip_types('application/javascript application/json application/xml text/css text/javascript ' \
          'text/plain', soft: true)

        c.add_header('Referrer-Policy', "'same-origin' always")
        c.add_header('Strict-Transport-Security', "'max-age=31536000; includeSubDomains' always") if @ssl
        c.add_header('X-Content-Type-Options', "'nosniff' always")
        c.add_header('X-Frame-Options', "'DENY' always")
        c.add_header('X-XSS-Protection', "'1; mode=block' always")

        c.set('$normalized', "http#{'s' if @ssl}://#{@var_prefix}_host#{@var_prefix}_port" \
          "#{@var_prefix}_uri#{@var_prefix}_query")

        c << <<~CONFIG
          if ($normalized != '$scheme://$host#{@var_prefix}_request_port$request_uri') {
            return 308 $normalized;
          }
        CONFIG

        c.location('/') do
          c.proxy_pass("http://#{@host}")
          c.proxy_redirect('off')
          c.proxy_set_header('Host', '$http_host')
          c.proxy_set_header('X-Real-IP', '$remote_addr')
          c.proxy_set_header('X-Forwarded-For', '$proxy_add_x_forwarded_for')
          c.proxy_set_header('X-Forwarded-Proto', @ssl ? 'https' : 'http')
          c.proxy_set_header('X-Forwarded-Port', "#{@var_prefix}_x_forwarded_port")
        end

        add_deprecated_config(@deprecated_additional_config)
      end
    end

    # Internal: Write the Nginx configuration to the (inactive) configuration file.
    #
    # Returns nothing.
    def write_config
      File.write(@config_file_inactive, config.to_s)
    end

    # Internal: Rename the inactive Nginx configuration file to its active name.
    #
    # Returns nothing.
    def activate_config
      FileUtils.mv(@config_file_inactive, @config_file_active)
    end

    # Internal: Rename the active Nginx configuration file to its inactive name.
    #
    # Returns nothing.
    def deactivate_config
      FileUtils.mv(@config_file_active, @config_file_inactive) if File.exist?(@config_file_active)
    end

    # Internal: Ensure hosts are mapped to localhost in the system /etc/hosts file if ensure_host_entries is
    # enabled. Useful in development. Uses sudo to perform the write, which will prompt for the system
    # user's password.
    #
    # Returns nothing.
    def ensure_host_entries
      return unless @ensure_host_entries

      content = File.read('/etc/hosts')
      missing_entries = @server_names.each_with_object([]) do |h, a|
        a << h unless content.include?(" #{h}\n")
      end

      return if missing_entries.empty?

      log('Writing host entries to /etc/hosts...')

      run(
        <<~CMD
          sudo sh -c 'printf "
          #{missing_entries.map { |h| "127.0.0.1 #{h}\n::1       #{h}"}.join("\n")}
          " >> /etc/hosts'
        CMD
      )
    end

    # Internal: Ensure Nginx's base configuration file contains an include statement for Potluck's Nginx
    # configuration files. Sudo is not used, so Nginx's base configuration file must be writable by the
    # system user running this Ruby process.
    #
    # Returns nothing.
    def ensure_include
      config_file = `nginx -t 2>&1`[TEST_CONFIG_REGEX, :config]
      config_content = File.read(config_file)

      if config_content !~ INCLUDE_REGEX
        File.write(config_file, config_content.sub(/^( *http *{)( *\n?)( *)/,
          "\\1\\2\\3include #{ACTIVE_CONFIG_PATTERN};\n\n\\3"))
      end
    end

    # Internal: Generate self-signed certificate files if SSL is enabled, custom certificate files are not
    # configured, and self-signed certificate files don't exist, will expire soon, or already did expire.
    #
    # Returns nothing.
    def ensure_ssl_files
      return unless @ssl

      csr = File.join(@dir, "#{@host}.csr")
      ssl_certificate, ssl_certificate_key, ssl_dhparam, auto_generated = ssl_config_values

      if auto_generated
        config.server(0) do |c|
          c.ssl_stapling('off')
          c.ssl_stapling_verify('off')
        end
      end

      return if !auto_generated || (
        csr && File.exist?(csr) &&
        ssl_certificate && File.exist?(ssl_certificate) &&
        ssl_certificate_key && File.exist?(ssl_certificate_key) &&
        ssl_dhparam && File.exist?(ssl_dhparam) && (
          Time.parse(run("openssl x509 -enddate -noout -in #{ssl_certificate}").sub('notAfter=', '')) -
          Time.now
        ) >= SSL_CERT_RENEW_DAYS * 24 * 60 * 60
      )

      log('Generating SSL files...')

      run("openssl genrsa -out #{ssl_certificate_key} 4096", capture_stderr: false)
      run("openssl req -out #{csr} -key #{ssl_certificate_key} -new -sha256 -config /dev/stdin <<< " \
        "'#{openssl_config}'", capture_stderr: false)
      run("openssl x509 -in #{csr} -out #{ssl_certificate} -signkey #{ssl_certificate_key} -days " \
        "#{SSL_CERT_DAYS} -req -sha256 -extensions req_ext -extfile /dev/stdin <<< '#{openssl_config}'",
        capture_stderr: false)
      run("openssl dhparam -out #{ssl_dhparam} 2048", capture_stderr: false)

      add_cert_to_keychain(ssl_certificate)
    end

    # Internal: Add a self-signed SSL certificate file to the system keychain if running on macOS. Uses sudo
    # to perform the write, which will prompt for the system user's password.
    #
    # ssl_certificate - String path to the SSL certificate file.
    #
    # Returns nothing.
    def add_cert_to_keychain(ssl_certificate)
      return unless RUBY_PLATFORM[/darwin/]

      log('Adding cert to keychain...')

      run(
        "sudo security delete-certificate -t -c #{@host} 2>&1 || " \
        "sudo security delete-certificate -c #{@host} 2>&1 || :"
      )

      run('sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ' \
        "#{ssl_certificate}")
    end

    # Internal: Get and validate the current configured SSL certificate files.
    #
    # Returns an Array of String paths to the SSL certificate, key, and DH parameter files, plus a boolean
    #   indicating if the files are auto-generated.
    def ssl_config_values
      ssl_certificate = config.dig('server', 0, 'ssl_certificate', 0)
      ssl_certificate_key = config.dig('server', 0, 'ssl_certificate_key', 0)
      ssl_dhparam = config.dig('server', 0, 'ssl_dhparam', 0)

      auto_generated = ssl_certificate == @default_ssl_certificate &&
                       ssl_certificate_key == @default_ssl_certificate_key &&
                       ssl_dhparam == @default_ssl_dhparam

      if !auto_generated && (
        ssl_certificate == @default_ssl_certificate ||
        ssl_certificate.nil? ||
        ssl_certificate_key == @default_ssl_certificate_key ||
        ssl_certificate_key.nil? ||
        ssl_dhparam == @default_ssl_dhparam ||
        ssl_dhparam.nil?
      )
        raise('Nginx configuration must provide all three SSL file directives (or none): ' \
          'ssl_certificate, ssl_certificate_key, ssl_dhparam')
      end

      [ssl_certificate, ssl_certificate_key, ssl_dhparam, auto_generated]
    end

    # Internal: Get the OpenSSL configuration content used when auto-generating an SSL certificate.
    #
    # Returns the String configuration.
    def openssl_config
      <<~OPENSSL
        [ req ]
        prompt             = no
        default_bits       = 4096
        distinguished_name = req_distinguished_name
        req_extensions     = req_ext

        [ req_distinguished_name ]
        commonName = #{@host}

        [ req_ext ]
        subjectAltName = @alt_names

        [alt_names]
        DNS.1 = #{@host}
        DNS.2 = *.#{@host}
      OPENSSL
    end

    # Internal: Iterate over a hash of config directives in the old deprecated style and add them.
    #
    # hash - Hash of config directives.
    #
    # Returns nothing.
    def add_deprecated_config(hash)
      return unless hash

      config do |c|
        hash.each do |directive, value|
          if !value.kind_of?(Hash)
            c.send(directive, value)
          elsif value[:repeat]
            value.each do |k, v|
              c.send(directive, k, v) unless k == :repeat
            end
          else
            c.send(directive) do
              add_deprecated_config(value)
            end
          end
        end
      end
    end
  end
end
