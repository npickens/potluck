# frozen_string_literal: true

require_relative('potluck/service')
require_relative('potluck/version')

module Potluck
  DIR = File.expand_path(File.join(ENV['HOME'], '.potluck')).freeze
  IS_MACOS = !!RUBY_PLATFORM[/darwin/]
end
