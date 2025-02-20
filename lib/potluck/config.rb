# frozen_string_literal: true

module Potluck
  # Configuration settings for Potluck services.
  class Config
    DEFAULT_DIR = File.expand_path(File.join(Dir.home, '.potluck')).freeze
    OLD_HOMEBREW_PREFIX = '/usr/local'

    attr_writer(:dir, :homebrew_prefix)

    # Public: Create a new instance.
    #
    # dir:             - String path to a directory to store files in.
    # homebrew_prefix: - String path to Homebrew's root directory.
    def initialize(dir: nil, homebrew_prefix: nil)
      self.dir = dir if dir
      self.homebrew_prefix = homebrew_prefix if homebrew_prefix
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
