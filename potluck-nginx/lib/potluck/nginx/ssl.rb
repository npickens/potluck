# frozen_string_literal: true

require('time')

module Potluck
  class Nginx < Dish
    class SSL
      # Based on https://hackernoon.com/how-properly-configure-nginx-server-for-tls-sg1d3udt
      DEFAULT_CONFIG = {
        'ssl_ciphers' => 'ECDH+AESGCM:ECDH+AES256-CBC:ECDH+AES128-CBC:DH+3DES:!ADH:!AECDH:!MD5',
        'ssl_prefer_server_ciphers' => 'on',
        'ssl_protocols' => 'TLSv1.2 TLSv1.3',
        'ssl_session_cache' => 'shared:SSL:40m',
        'ssl_session_tickets' => 'on',
        'ssl_session_timeout' => '4h',
        'add_header' => {
          repeat: true,
          'Strict-Transport-Security' => '\'max-age=31536000; includeSubDomains\' always',
        }.freeze,
      }.freeze

      CERT_DAYS = 365
      CERT_RENEW_DAYS = 14

      attr_reader(:csr_file, :key_file, :crt_file, :dhparam_file, :config)

      def initialize(nginx, dir, host, crt_file: nil, key_file: nil, dhparam_file: nil,
          config: {})
        @nginx = nginx
        @dir = dir
        @host = host

        @auto_generated = !crt_file && !key_file && !dhparam_file

        if !@auto_generated && (!crt_file || !key_file || !dhparam_file)
          raise('Must supply values for all three or none: crt_file, key_file, dhparam_file')
        end

        @csr_file = File.join(@dir, "#{@host}.csr").freeze
        @crt_file = crt_file || File.join(@dir, "#{@host}.crt").freeze
        @key_file = key_file || File.join(@dir, "#{@host}.key").freeze
        @dhparam_file = dhparam_file || File.join(@dir, 'dhparam.pem').freeze

        @config = {
          'ssl_certificate' => @crt_file,
          'ssl_certificate_key' => @key_file,
          'ssl_dhparam' => @dhparam_file,
          'ssl_stapling' => ('on' unless @auto_generated),
          'ssl_stapling_verify' => ('on' unless @auto_generated),
        }.merge!(DEFAULT_CONFIG).merge!(config)
      end

      def ensure_files
        return if !@auto_generated || (
          File.exists?(@csr_file) &&
          File.exists?(@key_file) &&
          File.exists?(@crt_file) &&
          File.exists?(@dhparam_file) &&
          (Time.parse(
            @nginx.run("openssl x509 -enddate -noout -in #{@crt_file}").sub('notAfter=', '')
          ) - Time.now) >= CERT_RENEW_DAYS * 24 * 60 * 60
        )

        @nginx.log('Generating SSL files...')

        @nginx.run("openssl genrsa -out #{@key_file} 4096", redirect_stderr: false)
        @nginx.run("openssl req -out #{@csr_file} -key #{@key_file} -new -sha256 -config /dev/stdin <<< "\
          "'#{openssl_config}'", redirect_stderr: false)
        @nginx.run("openssl x509 -in #{@csr_file} -out #{@crt_file} -signkey #{@key_file} -days "\
          "#{CERT_DAYS} -req -sha256 -extensions req_ext -extfile /dev/stdin <<< '#{openssl_config}'",
          redirect_stderr: false)
        @nginx.run("openssl dhparam -out #{@dhparam_file} 2048", redirect_stderr: false)

        if IS_MACOS
          @nginx.log('Adding cert to keychain...')

          @nginx.run(
            "sudo security delete-certificate -t -c #{@host} 2>&1 || "\
            "sudo security delete-certificate -c #{@host} 2>&1 || :"
          )

          @nginx.run("sudo security add-trusted-cert -d -r trustRoot -k "\
            "/Library/Keychains/System.keychain #{@crt_file}")
        end
      end

      private

      def openssl_config
        <<~EOS
          [ req ]
          prompt             = no
          default_bits       = 4096
          distinguished_name = req_distinguished_name
          req_extensions     = req_ext

          [ req_distinguished_name ]
          commonName          = #{@host}

          [ req_ext ]
          subjectAltName = @alt_names

          [alt_names]
          DNS.1 = #{@host}
          DNS.2 = *.#{@host}
        EOS
      end
    end
  end
end
