# frozen_string_literal: true

require_relative('potluck/service')

module Potluck
  DIR = File.expand_path(File.join(ENV['HOME'], '.potluck')).freeze
end
