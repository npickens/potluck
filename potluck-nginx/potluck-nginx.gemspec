# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('potluck-nginx', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'A Ruby manager for Nginx.'
  spec.description   = 'An extension to the Potluck gem that provides control over the Nginx process and '\
                       'its configuration files from Ruby.'
  spec.homepage      = 'https://github.com/npickens/potluck/tree/master/potluck-nginx'
  spec.license       = 'MIT'
  spec.files         = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'VERSION']

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.required_ruby_version = '>= 3.0.0'
  spec.required_rubygems_version = '>= 2.0.0'

  spec.add_dependency('potluck', version)
  spec.add_development_dependency('minitest', '~> 5.24')
  spec.add_development_dependency('minitest-reporters', '~> 1.7')
end
