# frozen_string_literal: true

require_relative('potluck/service')
require_relative('potluck/version')

module Potluck
  DIR = File.expand_path(File.join(ENV['HOME'], '.potluck')).freeze
  IS_MACOS = !!RUBY_PLATFORM[/darwin/]
  HOMEBREW_PREFIX = ENV['HOMEBREW_PREFIX'] || '/usr/local'
end
