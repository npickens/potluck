# frozen_string_literal: true

unless Dir.pwd == (base_dir = File.dirname(__dir__))
  ENV['BUNDLE_GEMFILE'] = File.join(base_dir, 'Gemfile')
end

require('bundler/setup')
require('minitest/autorun')
require('minitest/reporters')
require('potluck')

module Minitest
  def self.plugin_index_init(options)
    return unless options[:filter].to_i.to_s == options[:filter]

    options[:filter] = "/^test_#{options[:filter]}: /"
  end

  register_plugin('index')

  Reporters.use!(Reporters::ProgressReporter.new)
end

module TestHelper
  TMP_DIR = File.join(__dir__, 'tmp').freeze

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def test(description, &block)
      @@test_count ||= 0
      @@test_count += 1

      method_name =
        "test_#{@@test_count}: " \
        "#{name.chomp('Test') unless description.match?(/^[A-Z]/)}" \
        "#{' ' unless description.match?(/^[A-Z#.]/)}" \
        "#{description}"

      define_method(method_name, &block)
    end
  end
end
