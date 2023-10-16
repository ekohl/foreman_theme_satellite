require File.expand_path('../lib/foreman_theme_satellite/version', __FILE__)

Gem::Specification.new do |s|
  s.name        = 'foreman_theme_satellite'
  s.version     = ForemanThemeSatellite::VERSION
  s.metadata    = { "is_foreman_plugin" => "true" }
  s.license     = 'GPL-3.0'
  s.authors     = ['Alon Goldboim, Shimon Stein']
  s.email       = ['agoldboi@redhat.com']
  s.homepage    = 'https://github.com/theforeman/foreman_theme_satellite'
  s.summary     = 'This is a plugin that enables building a theme for Foreman.'
  # also update locale/gemspec.rb
  s.description = 'Theme changes for Satellite 6.'
  s.files = Dir['{app,config,db,lib,locale,webpack}/**/*'] +
            ['LICENSE', 'Rakefile', 'README.md'] +
            ['package.json']
  s.files -= Dir['**/*.orig']
  s.test_files = Dir['test/**/*'] + Dir['webpack/**/__tests__/*.js']

  s.add_dependency "deface"
  s.add_dependency "activesupport"
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-minitest'
  s.add_development_dependency 'rubocop-performance'
  s.add_development_dependency 'rubocop-rails'
  s.add_development_dependency 'rdoc'
end
