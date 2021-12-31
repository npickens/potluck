# frozen_string_literal: true

module Potluck
  class Nginx < Service
    ##
    # Utility methods for Nginx class.
    #
    class Util
      ##
      # Merges N hashes by merging nested hashes rather than overwriting them as is the case with
      # <tt>Hash#merge</tt>.
      #
      # * +hashes+ - Hashes to deep merge.
      # * +arrays+ - True if arrays should be merged rather than overwritten (optional, default: false).
      #
      # Example:
      #
      #   h1 = {hello: {item1: 'world'}}
      #   h2 = {hello: {item2: 'friend'}}
      #
      #   Util.deep_merge(h1, h2)
      #   # => {hello: {item1: 'world', item2: 'friend'}}
      #
      # By default only hashes are merged and arrays are still overwritten as they are with
      # <tt>Hash#merge</tt>. Passing <tt>arrays: true</tt> will result in arrays being merged similarly to
      # hashes. Example:
      #
      #   h1 = {hello: {item1: ['world']}}
      #   h2 = {hello: {item1: ['friend']}}
      #
      #   Util.deep_merge(h1, h2, arrays: true)
      #   # => {hello: {item1: ['world', 'friend']}}
      #
      def self.deep_merge(*hashes, arrays: false)
        hash = hashes[0].dup

        hashes[1..-1].each do |other_hash|
          other_hash.each do |key, other_value|
            this_value = hash[key]

            if this_value.kind_of?(Hash) && other_value.kind_of?(Hash)
              hash[key] = deep_merge(this_value, other_value, arrays: arrays)
            elsif arrays && this_value.kind_of?(Array)
              hash[key] |= Array(other_value)
            else
              hash[key] = other_value
            end
          end
        end

        hash
      end
    end
  end
end
