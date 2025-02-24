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

  spec.metadata      = {
    'bug_tracker_uri' => 'https://github.com/npickens/potluck/issues',
    'documentation_uri' => "https://github.com/npickens/potluck/blob/#{version}/potluck-postgres/README.md",
    'source_code_uri' => "https://github.com/npickens/potluck/tree/#{version}/potluck-postgres",
  }

  spec.required_ruby_version = '>= 3.0.0'
  spec.required_rubygems_version = '>= 2.0.0'

  spec.add_dependency('potluck', version)
  spec.add_dependency('pg', '~> 1.2')
  spec.add_dependency('sequel', '~> 5.41')
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('minitest', '~> 5.24')
  spec.add_development_dependency('minitest-reporters', '~> 1.7')
end
