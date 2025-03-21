# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('potluck', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'An extensible Ruby framework for managing external processes.'
  spec.description   = 'Potluck provides a simple interface for managing external processes in a way ' \
                       'that plays nice with others as well as smoothly handling both development and ' \
                       'production environments. Current official gem extensions provide Nginx and ' \
                       'Postgres management.'
  spec.homepage      = 'https://github.com/npickens/potluck'
  spec.license       = 'MIT'
  spec.files         = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'VERSION']

  spec.metadata      = {
    'bug_tracker_uri' => 'https://github.com/npickens/potluck/issues',
    'documentation_uri' => "https://github.com/npickens/potluck/blob/#{version}/README.md",
    'source_code_uri' => "https://github.com/npickens/potluck/tree/#{version}",
  }

  spec.required_ruby_version = '>= 3.0.0'
  spec.required_rubygems_version = '>= 2.0.0'

  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('logger', '~> 1.6.6')
  spec.add_development_dependency('minitest', '~> 5.24')
  spec.add_development_dependency('minitest-reporters', '~> 1.7')
end
