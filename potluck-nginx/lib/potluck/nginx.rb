# frozen_string_literal: true

require('fileutils')
require('potluck')
require_relative('nginx/ssl')
require_relative('nginx/util')

module Potluck
  class Nginx < Dish
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

    def initialize(hosts, port, subdomains: nil, ssl: nil, one_host: false, www: nil, multiple_slashes: nil,
        multiple_question_marks: nil, trailing_slash: nil, trailing_question_mark: nil, config: {},
        ensure_host_entries: false, **args)
      if args[:manage] && !args[:manage].kind_of?(Hash) && !launchctl?
        args[:manage] = NON_LAUNCHCTL_COMMANDS
      end

      super(**args)

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

      FileUtils.mkdir_p(DIR)
      FileUtils.mkdir_p(@dir)

      @config_file_active = File.join(@dir, CONFIG_NAME_ACTIVE).freeze
      @config_file_inactive = File.join(@dir, CONFIG_NAME_INACTIVE).freeze
    end

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

    def stop(hard = false)
      return unless manage?

      deactivate_config

      hard || status != :active ? super() : reload
    end

    def reload
      return unless manage?

      run('nginx -s reload')
    end

    private

    def config
      host_subdomains_regex = ([@host] + @subdomains).join('|')
      hosts_subdomains_regex = (@hosts + @subdomains).join('|')

      config = {
        "upstream #{@host}" => {
          'server' => "127.0.0.1:#{@port}",
        },

        'server' => Util.deep_merge!({
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
            'Referrer-Policy' => 'same-origin',
            'X-Frame-Options' => 'DENY',
            'X-XSS-Protection' => '\'1; mode=block\'',
            'X-Content-Type-Options' => 'nosniff',
          },
        }, @ssl ? @ssl.config : {}).merge!(
          'location /' => {
            raw: """
              if ($host !~ ^#{hosts_subdomains_regex}$) { return 404; }

              set $r 0;
              set $s $scheme;
              set $h $host;
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
              if ($http_host ~ :[0-9]+$) { set $p :#{@ssl ? '4433' : '8080'}; }
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
              'Host' => @host,
              'X-Real-IP' => '$remote_addr',
              'X-Forwarded-For' => '$proxy_add_x_forwarded_for',
              'X-Forwarded-Proto' => @ssl ? 'https' : 'http',
              'X-Forwarded-Port' => @ssl ? '443' : '80',
            },
          },
        ),
      }

      Util.deep_merge!(config['server'], @additional_config)

      config
    end

    def write_config
      File.open(@config_file_inactive, 'w') do |file|
        file.write(self.class.to_nginx_config(config))
      end
    end

    def activate_config
      FileUtils.mv(@config_file_inactive, @config_file_active)
    end

    def deactivate_config
      FileUtils.mv(@config_file_active, @config_file_inactive) if File.exists?(@config_file_active)
    end

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

    def ensure_include
      config_file = `nginx -t 2>&1`[TEST_CONFIG_REGEX, :config]
      config_content = File.read(config_file)

      if config_content !~ INCLUDE_REGEX
        File.write(config_file, config_content.sub(/^( *http *{)( *\n?)( *)/,
          "\\1\\2\\3include #{ACTIVE_CONFIG_PATTERN};\n\n\\3"))
      end
    end

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

    def self.plist
      super(
        <<~EOS
          <key>ProgramArguments</key>
          <array>
            <string>/usr/local/opt/nginx/bin/nginx</string>
            <string>-g</string>
            <string>daemon off;</string>
          </array>
          <key>StandardOutPath</key>
          <string>/usr/local/var/log/nginx/access.log</string>
          <key>StandardErrorPath</key>
          <string>/usr/local/var/log/nginx/error.log</string>
        EOS
      )
    end
  end
end
