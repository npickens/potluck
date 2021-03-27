# frozen_string_literal: true

require_relative('potluck/dish')

module Potluck
  DIR = File.expand_path(File.join(ENV['HOME'], '.potluck')).freeze
  IS_MACOS = !!RUBY_PLATFORM[/darwin/]
end
