# frozen_string_literal: true

require('minitest/autorun')
require('minitest/reporters')
require_relative('../lib/potluck')

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

  Potluck.send(:remove_const, :DIR)
  Potluck.const_set(:DIR, TMP_DIR)

  ##########################################################################################################
  ## Testing                                                                                              ##
  ##########################################################################################################

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
