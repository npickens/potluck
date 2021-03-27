# frozen_string_literal: true

module Potluck
  class Nginx
    class Util
      def self.deep_merge!(*hashes, arrays: false)
        hash = hashes[0]

        hashes[1..-1].each do |other_hash|
          other_hash.each do |key, other_value|
            this_value = hash[key]

            if this_value.kind_of?(Hash) && other_value.kind_of?(Hash)
              deep_merge!(this_value, other_value, arrays: arrays)
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
