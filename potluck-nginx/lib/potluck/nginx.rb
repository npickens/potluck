# frozen_string_literal: true

require('fileutils')
require('potluck')
require_relative('nginx/ssl')
require_relative('nginx/util')
require_relative('nginx/version')

module Potluck
  # A Ruby interface for configuring and controlling Nginx. Each instance of this class manages a separate
  # Nginx configuration file, which is loaded and unloaded from the base Nginx configuration when #start and
  # #stop are called, respectively. Any number of Ruby processes can thus each manage their own Nginx
  # configuration and control whether or not it is active without interfering with any other instances or
  # non-Ruby processes leveraging Nginx.
  class Nginx < Service
    CONFIG_NAME_ACTIVE = 'nginx.conf'
    CONFIG_NAME_INACTIVE = 'nginx-stopped.conf'
    ACTIVE_CONFIG_PATTERN = File.join(DIR, '*', CONFIG_NAME_ACTIVE).freeze

    TEST_CONFIG_REGEX = /nginx: configuration file (?<config>.+) test (failed|is successful)/.freeze
    INCLUDE_REGEX = /^ *include +#{Regexp.escape(ACTIVE_CONFIG_PATTERN)} *;/.freeze

    NON_LAUNCHCTL_COMMANDS = {
      status: 'ps aux | grep \'[n]ginx: master process\'',
      start: 'nginx',
      stop: 'nginx -s stop',
    }.freeze

    # Public: Create a new instance.
    #
    # hosts                    - String or Array of String hosts.
    # port                     - Integer port that the upstream (Ruby web server) is running on.
    # subdomains:              - String or Array of String subdomains.
    # ssl:                     - Hash of SSL configuration arguments to pass to SSL.new.
    # one_host:                - Boolean specifying if URLs should be normalized to the first item in the
    #                            hosts array.
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
    # config:                  - Nginx configuration Hash (see #config).
    # ensure_host_entries:     - Booelan specifying if hosts should be added to system /etc/hosts file as
    #                            mappings to localhost.
    # kwargs                   - Hash of keyword arguments to pass to Service.new.
    def initialize(hosts, port, subdomains: nil, ssl: nil, one_host: false, www: nil, multiple_slashes: nil,
        multiple_question_marks: nil, trailing_slash: nil, trailing_question_mark: nil, config: {},
        ensure_host_entries: false, **kwargs)
      if kwargs[:manage] && !kwargs[:manage].kind_of?(Hash) && !self.class.launchctl?
        kwargs[:manage] = NON_LAUNCHCTL_COMMANDS
      end

      super(**kwargs)

      @hosts = Array(hosts).map { |h| h.sub(/^www\./, '') }.uniq
      @hosts += @hosts.map { |h| "www.#{h}" }
      @host = @hosts.first
      @port = port

      @ensure_host_entries = ensure_host_entries
      @dir = File.join(DIR, @host)
      @ssl = SSL.new(self, @dir, @host, **ssl) if ssl

      @scheme = @ssl ? 'https' : 'http'
      @other_scheme = @ssl ? 'http' : 'https'
      @one_host = !!one_host
      @subdomains = Array(subdomains)
      @www = www
      @multiple_slashes = multiple_slashes
      @multiple_question_marks = multiple_question_marks
      @trailing_slash = trailing_slash
      @trailing_question_mark = trailing_question_mark
      @additional_config = config

      FileUtils.mkdir_p(@dir)

      @config_file_active = File.join(@dir, CONFIG_NAME_ACTIVE).freeze
      @config_file_inactive = File.join(@dir, CONFIG_NAME_INACTIVE).freeze
    end

    # Public: Ensure this instance's configuration file is active and start Nginx. If Nginx is already
    # running, send a reload signal to the process after activating the configuration file. Does nothing if
    # Nginx is not managed.
    #
    # Returns nothing.
    def start
      return unless manage?

      @ssl&.ensure_files
      ensure_host_entries if @ensure_host_entries
      ensure_include

      write_config
      activate_config

      run('nginx -t')

      status == :active ? reload : super
    end

    # Public: Ensure this instance's configuration file is inactive and optionally stop Nginx. Does nothing
    # if Nginx is not managed.
    #
    # hard - Boolean specifying if the Nginx process should be stopped (true) or  this instance's
    #        configuration file should just be inactivated (false).
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

    # Public: Return the content for the Nginx configuration file.
    #
    # Returns the String content.
    def config_file_content
      self.class.to_nginx_config(config)
    end

    # Public: Get the content of the launchctl plist file.
    #
    # Returns the String content.
    def self.plist
      super(
        <<~EOS
          <key>ProgramArguments</key>
          <array>
            <string>#{HOMEBREW_PREFIX}/opt/nginx/bin/nginx</string>
            <string>-g</string>
            <string>daemon off;</string>
          </array>
          <key>StandardOutPath</key>
          <string>#{HOMEBREW_PREFIX}/var/log/nginx/access.log</string>
          <key>StandardErrorPath</key>
          <string>#{HOMEBREW_PREFIX}/var/log/nginx/error.log</string>
        EOS
      )
    end

    # Public: Convert a hash to an Nginx configuration file content string. Keys are strings and values
    # either strings or hashes. Symbol keys are used as special directives. A nil value in a hash will
    # result in that key-value pair being omitted.
    #
    # hash   - Hash of String keys and String or Hash values to convert to the string content of an Nginx
    #          configuration file.
    # indent - Integer number of spaces to indent (used when the method is called recursively and should not
    #          be set explicitly).
    # repeat - String value to prepend to each entry of the hash (used when the method is called recursively
    #          and should not be set explicitly).
    #
    # Examples
    #
    #   # {repeat: true, ...} will cause the parent hash's key to be prefixed to each line of the output.
    #
    #   Nginx.to_nginx_config(
    #     'add_header' => {
    #       repeat: true,
    #       'X-Frame-Options' => 'DENY',
    #       'X-Content-Type-Options' => 'nosniff',
    #     }
    #   )
    #
    #   # => "add_header X-Frame-Options DENY;
    #   #     add_header X-Content-Type-Options nosniff;"
    #
    #   # {raw: "..." can be used to include a raw chunk of text rather than key-value pairs.
    #
    #   Nginx.to_nginx_config(
    #     'location /' => {
    #       raw: """
    #         if ($scheme = https) { ... }
    #         if ($host ~ ^www.) { ... }
    #       """,
    #     }
    #   )
    #
    #   # => "location / {
    #   #       if ($scheme = https) { ... }
    #   #       if ($host ~ ^www.) { ... }
    #   #     }"
    #
    # Returns the Nginx configuration String.
    def self.to_nginx_config(hash, indent: 0, repeat: nil)
      hash.each_with_object(+'') do |(k, v), config|
        next if v.nil?
        next if k == :repeat

        config << (
          if v.kind_of?(Hash)
            if v[:repeat]
              to_nginx_config(v, indent: indent, repeat: k)
            else
              "#{' ' * indent}#{k} {\n#{to_nginx_config(v, indent: indent + 2)}#{' ' * indent}}\n"
            end
          elsif k == :raw
            "#{v.gsub(/^(?=.)/, ' ' * indent)}\n\n"
          else
            "#{' ' * indent}#{"#{repeat} " if repeat}#{k}#{" #{v}" unless v == true};\n"
          end
        )
      end
    end

    private

    # Internal: Get a hash representation of the Nginx configuration file content. Any configuration passed
    # to Nginx.new is deep-merged into a base configuration hash, meaning nested hashes are merged rather
    # than overwritten (see Util.deep_merge).
    #
    # Returns the Hash configuration.
    def config
      host_subdomains_regex = ([@host] + @subdomains).join('|')
      hosts_subdomains_regex = (@hosts + @subdomains).join('|')

      config = {
        "upstream #{@host}" => {
          'server' => "127.0.0.1:#{@port}",
        },

        'server' => Util.deep_merge(
          {
            'charset' => 'UTF-8',
            'access_log' => File.join(@dir, 'nginx-access.log'),
            'error_log' => File.join(@dir, 'nginx-error.log'),

            'listen' => {
              repeat: true,
              '8080' => true,
              '[::]:8080' => true,
              '4433 ssl http2' => @ssl ? true : nil,
              '[::]:4433 ssl http2' => @ssl ? true : nil,
            },
            'server_name' => (@hosts + @subdomains).join(' '),

            'gzip' => 'on',
            'gzip_types' => 'application/javascript application/json application/xml text/css '\
              'text/javascript text/plain',

            'add_header' => {
              repeat: true,
              'Referrer-Policy' => '\'same-origin\' always',
              'X-Frame-Options' => '\'DENY\' always',
              'X-XSS-Protection' => '\'1; mode=block\' always',
              'X-Content-Type-Options' => '\'nosniff\' always',
            },
          },

          @ssl ? @ssl.config : {},

          {
            'location /' => {
              raw: """
                if ($host !~ ^#{hosts_subdomains_regex}$) { return 404; }

                set $r 0;
                set $s $scheme;
                set $h $host;
                set $port #{@ssl ? '443' : '80'};
                set $p '';
                set $u '';
                set $q '';

                #{if @www.nil? && @one_host == false
                  nil
                elsif @www.nil? && @one_host == true
                  "if ($host !~ ^(www.)?#{host_subdomains_regex}$) { set $h $1#{@host}; set $r 1; }"
                elsif @www == false && @one_host == false
                  "if ($host ~ ^www.(.+)$) { set $h $1; set $r 1; }"
                elsif @www == false && @one_host == true
                  "if ($host !~ ^#{host_subdomains_regex}$) { set $h #{@host}; set $r 1; }"
                elsif @www == true && @one_host == false
                  "if ($host !~ ^www.(.+)$) { set $h $1; set $r 1; }"
                elsif @www == true && @one_host == true
                  "if ($host !~ ^www.#{host_subdomains_regex}$) { set $h www.#{@host}; set $r 1; }"
                end}

                if ($scheme = #{@other_scheme}) { set $s #{@scheme}; set $r 1; }
                if ($http_host ~ :([0-9]+)$) { set $p :$1; set $port $1; }
                if ($request_uri ~ ^([^\\?]+)(\\?+.*)?$) { set $u $1; set $q $2; }

                #{'if ($u ~ //) { set $u $uri; set $r 1; }' if @multiple_slashes == false}
                #{'if ($q ~ ^\?\?+(.*)$) { set $q ?$1; set $r 1; }' if @multiple_question_marks == false}

                #{if @trailing_question_mark == false
                  'if ($q ~ \?+$) { set $q \'\'; set $r 1; }'
                elsif @trailing_question_mark == true
                  'if ($q !~ .) { set $q ?; set $r 1; }'
                end}
                #{if @trailing_slash == false
                  'if ($u ~ (.+?)/+$) { set $u $1; set $r 1; }'
                elsif @trailing_slash == true
                  'if ($u ~ [^/]$) { set $u $u/; set $r 1; }'
                end}

                set $mr $request_method$r;

                if ($mr ~ ^(GET|HEAD)1$) { return 301 $s://$h$p$u$q; }
                if ($mr ~ 1$) { return 308 $s://$h$p$u$q; }
              """.strip.gsub(/^ +/, '').gsub(/\n{3,}/, "\n\n"),

              'proxy_pass' => "http://#{@host}",
              'proxy_redirect' => 'off',
              'proxy_set_header' => {
                repeat: true,
                'Host' => '$http_host',
                'X-Real-IP' => '$remote_addr',
                'X-Forwarded-For' => '$proxy_add_x_forwarded_for',
                'X-Forwarded-Proto' => @ssl ? 'https' : 'http',
                'X-Forwarded-Port' => '$port',
              },
            },
          },

          @additional_config,
        )
      }

      config
    end

    # Internal: Write the Nginx configuration to the (inactive) configuration file.
    #
    # Returns nothing.
    def write_config
      File.write(@config_file_inactive, config_file_content)
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

    # Internal: Ensure hosts are mapped to localhost in the system /etc/hosts file. Useful in development.
    # Uses sudo to perform the write, which will prompt for the system user's password.
    #
    # Returns nothing.
    def ensure_host_entries
      content = File.read('/etc/hosts')
      missing_entries = (@hosts + @subdomains).each_with_object([]) do |h, a|
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
  end
end
