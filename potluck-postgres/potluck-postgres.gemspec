# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('potluck-postgres', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'A Ruby manager for Postgres.'
  spec.description   = 'An extension to the Potluck gem that provides some basic utilities for setting up '\
                       'and connecting to Postgres databases, as well as control over the Postgres process.'
  spec.homepage      = 'https://github.com/npickens/potluck/tree/master/potluck-postgres'
  spec.license       = 'MIT'
  spec.files         = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'VERSION']

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = spec.homepage
  else
    raise('RubyGems 2.0 or newer is required to protect against public gem pushes.')
  end

  spec.required_ruby_version = '>= 2.5.8'

  spec.add_dependency('potluck', version)
  spec.add_dependency('pg', '~> 1.2')
  spec.add_dependency('sequel', '~> 5.41')

  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('minitest', '>= 5.11.2', '< 6.0.0')
end
