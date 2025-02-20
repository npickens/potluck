# frozen_string_literal: true

require_relative('potluck/config')
require_relative('potluck/service')
require_relative('potluck/version')

# Main module providing an extensible Ruby framework for managing external processes.
module Potluck
  @config = Config.new

  class << self
    attr_accessor(:config)
  end

  # Public: Change settings.
  #
  # Yields the Config instance used by Potluck services.
  #
  # Examples
  #
  #   Potluck.configure do |config|
  #     config.dir = '/etc/potluck'
  #     config.homebrew_prefix = '/custom/brew'
  #   end
  #
  # Returns nothing.
  def self.configure
    yield(config)
  end
end
