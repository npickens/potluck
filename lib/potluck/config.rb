# frozen_string_literal: true

module Potluck
  # Configuration settings for Potluck services.
  class Config
    DEFAULT_DIR = File.expand_path(File.join(Dir.home, '.potluck')).freeze
    OLD_HOMEBREW_PREFIX = '/usr/local'

    attr_writer(:dir, :homebrew_prefix)

    # Public: Create a new instance.
    #
    # Yields the instance being created.
    #
    # Examples
    #
    #   Config.new do |config|
    #     config.dir = '/etc/potluck'
    #     config.homebrew_prefix = '/custom/brew'
    #   end
    def initialize
      yield(self) if block_given?
    end

    # Public: Get the directory path setting.
    #
    # Returns the String value.
    def dir
      @dir || DEFAULT_DIR
    end

    # Public: Get the Homebrew prefix path setting.
    #
    # Returns the String value.
    def homebrew_prefix
      @homebrew_prefix || ENV['HOMEBREW_PREFIX'] || OLD_HOMEBREW_PREFIX
    end
  end
end
