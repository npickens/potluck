# frozen_string_literal: true

module Potluck
  class Nginx < Service
    # Utility methods for the Nginx class.
    class Util
      # Public: Merge N hashes by merging nested hashes rather than overwriting them as is the case with
      # Hash#merge.
      #
      # hashes  - Hashes to deep merge.
      # arrays: - Boolean specifying if arrays should be merged rather than overwritten.
      #
      # Examples
      #
      #   h1 = {hello: {item1: 'world'}}
      #   h2 = {hello: {item2: 'friend'}}
      #
      #   Util.deep_merge(h1, h2)
      #   # => {hello: {item1: 'world', item2: 'friend'}}
      #
      #   h1 = {hello: {item1: ['world']}}
      #   h2 = {hello: {item1: ['friend']}}
      #
      #   Util.deep_merge(h1, h2, arrays: true)
      #   # => {hello: {item1: ['world', 'friend']}}
      #
      # Returns the merged Hash.
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
