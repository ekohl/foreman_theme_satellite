#!/usr/bin/ruby

#needed gems
system 'gem install git'
system 'gem install get_pomo'
require 'pathname'
require 'git'
require 'yaml'
require 'get_pomo'


def clone_projects
  Git.clone('git@gitlab.sat.lab.tlv.redhat.com:satellite6/foreman_theme_satellite.git', 'foreman_theme_satellite', :path => '/tmp/rebase/')
  puts 'foreman_theme_satellite was cloned'
  plugin_config_file = YAML.load_file(Pathname.new('/tmp/rebase/foreman_theme_satellite/lib/plugins.yml'))
  plugin_config_file[:plugins].each do |plugin_name, val|
    g = Git.clone(val['git_url'].empty? ? 'https://github.com/theforeman/' + plugin_name + '.git' : val['git_url'], plugin_name, :path => '/tmp/rebase/')
    g.branch(val['git_branch']).checkout
    puts plugin_name + '    was cloned'
  end
end

def run_match_po
  clone_projects
  puts 'finished cloning projects starting matching po files'
  require '/tmp/rebase/foreman_theme_satellite/lib/locale_change'
  match_po
end

def run_after_translation
  after_translation
end


run_match_po
if ARGV[0] && ARGV[0].include?("full")
  run_after_translation
end
