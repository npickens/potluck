# frozen_string_literal: true

require('minitest')
require('potluck')

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
