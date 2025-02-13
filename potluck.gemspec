# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('potluck', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'An extensible Ruby framework for managing external processes.'
  spec.description   = 'Potluck provides a simple interface for managing external processes in a way that '\
                       'plays nice with others as well as smoothly handling both development and '\
                       'production environments. Current official gem extensions provide Nginx and '\
                       'Postgres management.'
  spec.homepage      = 'https://github.com/npickens/potluck'
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

  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('logger', '~> 1.6.6')
  spec.add_development_dependency('minitest', '~> 5.24')
  spec.add_development_dependency('minitest-reporters', '~> 1.7')
end
