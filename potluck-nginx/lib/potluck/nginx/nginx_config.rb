# frozen_string_literal: true

module Potluck
  class Nginx < Service
    # Public: Class for building and generating Nginx config file content. An instance of this class is
    # passed to the block given to Nginx.new and Nginx#config.
    #
    # The name NginxConfig was chosen over Config because this is specifically for generating an Nginx
    # config file--it is not for configuring the Potluck::Nginx class or an instance of it.
    #
    # Examples
    #
    #   nginx = Nginx.new('hello.world', 1234) do |c|
    #     c.server do
    #       c.access_log('/path/to/access.log')
    #       c.add_header('X-Greeting', "'hello' always")
    #     end
    #   end
    #
    #   # Add more configuration.
    #   nginx.config do |c|
    #     c.server do
    #       c.add_header('X-Subject', "'world' always")
    #     end
    #   end
    class NginxConfig
      # Internal: Wrapper for config values that should be overwritten when set again (by default, repeat
      # directives are appended to the config--they do not replace any previous occurrence). Used by
      # NginxConfig#add_directive when passed soft: true.
      class SoftValue < SimpleDelegator
      end

      # Internal: Regex for matching raw text items in the config hash. Raw text that gets added at various
      # points uses an incrementing Symbol key of the form :"raw[0]", :"raw[1]", :"raw[2]", ....
      RAW_KEY_REGEX = /^raw\[(?<index>\d+)\]$/

      # Public: Create a new instance.
      #
      # block - Block passed to #modify for defining the config.
      def initialize(&block)
        @config = {}
        @context = []

        modify(&block) if block
      end

      # Public: Modify this config.
      #
      # block - Block to execute for modifying the config. Self is passed to the block, accepting any method
      #         method called on it and transforming it into an Nginx configuration directive.
      #
      # Examples
      #
      #   config = NginxConfig.new
      #
      #   config.modify do |c|
      #     c.server do
      #       c.listen('80')
      #       c.listen('[::]:80')
      #       c.server_names('hello.world', 'hi.there')
      #     end
      #   end
      #
      # Returns self.
      def modify(&block)
        block.call(self) if block

        self
      end

      # Public: Append Nginx config content via raw text or hash content.
      #
      # content - String or Hash of Nginx config content (any other type is gracefully ignored). See
      #           #add_hash and #add_raw.
      #
      # Returns self.
      def <<(content)
        case content
        when Hash
          add_hash(content)
        when String
          add_raw(content)
        end

        self
      end

      # Public: Add an Nginx directive. See #add_block_directive and #add_directive.
      #
      # name   - Symbol name of the directive.
      # args   - Zero or more Object directive values.
      # kwargs - Hash of optional meta information for defining the directive.
      # block  - Block that adds child directives.
      #
      # Returns nil.
      # Raises NoMethodError if the named method is a defined private method (this replicates standard
      #   behavior for private methods).
      def method_missing(name, *args, **kwargs, &block)
        if private_method?(name)
          raise(NoMethodError, "private method '#{name}' called for an instance of #{self.class.name}")
        end

        if block
          add_block_directive(name, *args, &block)
        elsif !args.empty?
          add_directive(name, *args, **kwargs)
        end

        nil
      end

      # Public: Determine if this instance handles a particular method call.
      #
      # name            - Symbol name of the method.
      # include_private - Boolean indicating if private methods should be included in the check.
      #
      # Returns false if the method is private and include_private is false, and true otherwise (since
      #   #method_missing is implemented and accepts any method name).
      def respond_to?(name, include_private = false)
        private_method?(name) ? include_private : true
      end

      # Public: Generate the Nginx config file content.
      #
      # Returns the String content.
      def to_s
        to_nginx_config(@config)
      end

      # Public: Get the value of a directive.
      #
      # keys - One or more String directive names, Symbol raw keys (e.g. :"raw[0]"), or Integer array
      #        indexes.
      #
      # Returns the String, Array, or Hash directive value.
      def dig(*keys)
        @config.dig(*keys)
      end

      private

      # Internal: Transform a hash into raw content for an Nginx configuration file.
      #
      # hash    - Hash config definition.
      # indent: - Integer number of spaces to indent (used when the method is called recursively and should
      #           not be set explicitly).
      #
      # Returns the String content.
      def to_nginx_config(hash, indent: 0)
        hash.each.with_object(+'') do |(name, items), str|
          if name.kind_of?(Symbol) && name.match?(RAW_KEY_REGEX)
            str << items.gsub(/^(?=.)/, ' ' * indent)
            str << "\n" unless str.end_with?("\n")

            next
          end

          items.each do |item|
            if item.kind_of?(Hash)
              str << "#{' ' * indent}#{name} {\n" \
                     "#{to_nginx_config(item, indent: indent + 2)}" \
                     "#{' ' * indent}}\n"
            else
              str << "#{' ' * indent}#{name} #{item};\n"
            end
          end
        end
      end

      # Internal: Get the hash for the current context stack.
      #
      # Returns the contextual Hash.
      def contextual_config
        @context.empty? ? @config : @config.dig(*@context)
      end

      # Internal: Add an Nginx block directive.
      #
      # name  - String or Symbol name of the block directive.
      # args  - Zero or more Object values that are converted to strings (via #to_s) and joined to name with
      #         spaces; an optional last Integer item specifies the index into the array of directive values
      #         (used when there is more than one of the same directive, such as with server blocks).
      # block - Block that defines child directives.
      #
      # Examples
      #
      #   add_block_directive('server') do |c|
      #     c.listen('8080')
      #   end
      #
      #   add_block_directive('server', 1) do |c|
      #     c.listen('4433')
      #     c.server_name('hi.there')
      #   end
      #
      #   add_block_directive('server', 0) do |c|
      #     c.server_name('hello.world')
      #   end
      #
      #   to_s
      #
      #   # => "server {\n" +
      #   #    "  listen 8080;\n"
      #   #    "  server_name hello.world;\n"
      #   #    "}\n"
      #   #    "server {\n" +
      #   #    "  listen 4433;\n"
      #   #    "  server_name hi.there;\n"
      #   #    "}\n"
      #
      # Returns nothing.
      def add_block_directive(name, *args, &block)
        index = args.pop if args.last.kind_of?(Integer)
        context = "#{name} #{args.join(' ')}".strip
        directives = (contextual_config[context] ||= [])
        index ||= directives.size - 1

        unless directives[index]
          directives << {}
          index = directives.size - 1
        end

        @context << context << index

        block.call(self)

        @context.pop(2)
      end

      # Internal: Add an Nginx (non-block) directive.
      #
      # Repeated calls with the same name accumulate into an array. If there are two or more args,
      # subsequent calls with the same name and same first arg will overwrite the original value for that
      # name and first arg (see the examples if this is unclear).
      #
      # If args is empty or only contains nil and/or empty string values, any previously-added directive
      # with the same name is removed.
      #
      # If soft: true is passed, value is added but treated as 'soft'. Soft values are all removed as soon
      # as a non-soft value is added. This is used to set up default values that can be optionally
      # overwritten.
      #
      # name   - String or Symbol name of the directive.
      # args   - Zero or more Object values that are converted to strings (via #to_s) and joined to each
      #          other with spaces.
      # kwargs - Hash of optional meta information. Only :soft is used. Any others will be ignored.
      #
      # Examples
      #
      #   add_directive('add_header', 'Referrer-Policy', "'same-origin' always")
      #   add_directive('add_header', 'X-Frame-Options', "'SAMEORIGIN' always")
      #   add_directive('add_header', 'X-Frame-Options', "'DENY' always")
      #   to_s
      #
      #   # => "add_header Referrer-Policy 'same-origin' always;\n" +
      #   #    "add_header X-Frame-Options 'DENY' always;\n"
      #
      #   add_directive('add_header', 'Referrer-Policy', nil)
      #   to_s
      #
      #   # => "add_header X-Frame-Options 'DENY' always;\n"
      #
      #   access_log('/first/path/to/access.log', soft: true)
      #   access_log('/second/path/to/access.log', soft: true)
      #   to_s
      #
      #   # => "access_log /first/path/to/access.log;\n" +
      #   #    "access_log /second/path/to/access.log;\n"
      #
      #   access_log('/third/path/to/access.log')
      #   to_s
      #
      #   # => "access_log /third/path/to/access.log;\n"
      #
      # Returns nothing.
      def add_directive(name, *args, **kwargs)
        name = name.to_s
        directive = (contextual_config[name] ||= [])
        soft = kwargs[:soft]

        key = "#{args.first} " if args.size >= 2
        value = args.join(' ').strip
        value = nil if value.empty? || value == key&.strip
        value = SoftValue.new(value) if soft

        unless soft
          directive.reject! do |item|
            item.kind_of?(SoftValue)
          end
        end

        if key
          index = directive.index do |item|
            item.start_with?(key)
          end
        end

        if index
          value.nil? ? directive.delete_at(index) : (directive[index] = value)
        elsif value.nil?
          directive.clear
        else
          directive << value
        end

        contextual_config.delete(name) if directive.empty?
      end

      # Internal: Add Nginx config content using a hash.
      #
      # hash - Hash of config content. Keys are String directive names or the Symbol :raw or :raw[<i>]
      #        (where <i> is an Integer). Values are a Hash for block directive content, an Array of
      #        Object--each of which will have #to_s called on it--for repeated directives, or an Object
      #        which will have #to_s called on it.
      #
      # Examples
      #
      #   add_hash({
      #     'server' => {
      #       'access_log' => '/path/to/access.log',
      #       'add_header' => [
      #         "Referrer-Policy 'same-origin' always",
      #         "X-Frame-Options 'DENY' always",
      #       ],
      #       'raw[0]': 'return 404',
      #     },
      #   })
      #
      # Returns nothing.
      def add_hash(hash)
        hash.each do |key, value|
          if key == :raw || key.match?(RAW_KEY_REGEX)
            add_raw(value)
            next
          end

          case value
          when Hash
            add_block_directive(key) do
              add_hash(value)
            end
          when Array
            value.each do |item|
              add_directive(key, item)
            end
          else
            add_directive(key, value)
          end
        end
      end

      # Internal: Add raw Nginx config content using a string.
      #
      # content - String config content.
      #
      # Returns nothing.
      def add_raw(content)
        contextual_config[next_raw_key] = content
      end

      # Internal: Get the next hash key used for raw content. If the current context has, say, keys :raw[0]
      # and :raw[1], then :raw[2] will be returned.
      #
      # Returns the Symbol key.
      def next_raw_key
        index = contextual_config
          .keys
          .select { |k| k.match?(RAW_KEY_REGEX) }
          .map { |k| k[RAW_KEY_REGEX, :index].to_i }
          .last

        :"raw[#{(index || -1) + 1}]"
      end

      # Internal: Determine if a method is defined and is private.
      #
      # name - Symbol name of the method.
      #
      # Returns the boolean result.
      def private_method?(name)
        @@private_methods ||= self.class.private_instance_methods(false)
        @@private_methods.include?(name)
      end
    end
  end
end
