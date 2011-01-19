#! /usr/bin/env ruby

__DIR__ = File.expand_path('..', __FILE__)

%w[
  rubygems
  erb fileutils open3 yaml
  active_support/all filemagic maruku
  nuggets/util/content_type nuggets/util/i18n
  redcloth RMagick sinatra
].each { |lib|
  require lib
}

%w[
  git helpers page post routes series
].each { |lib|
  require File.join(__DIR__, 'lib', lib)
}

DEFAULT_OPTIONS = {
  :sessions => true,            # enable/disable cookie based sessions
  :logger   => nil,             # set Logger instance, or true
  :repo     => nil,             # set Git repo URL (required)
  :site     => nil,             # set site URL
  :staging  => nil,             # set staging URL
  :preview  => nil,             # set per-user preview URL
  :email    => '%s@localhost',  # set user's e-mail address (used for Git)

  # set temporary directory for Git repo clones
  :tmpdir => File.join(__DIR__, 'tmp'),

  # path to config file (not an option, really)
  :config => File.join(__DIR__, 'config.yaml'),

  # set list of files to ignore in folder listing
  :ignore => %w[
    . .. .git .gitignore
    _site _site.tmp _site.old
    _plugins favicon.ico
  ]
}

cfg = DEFAULT_OPTIONS.delete(:config)
opt = DEFAULT_OPTIONS.merge(File.readable?(cfg) ? YAML.load_file(cfg) : {})

abort 'No repo to serve!' unless opt[:repo]

if opt[:logger] == true
  require 'logger'
  opt[:logger] = Logger.new(STDERR)
end

configure { set opt }

include JekyllCommander::Routes
helpers JekyllCommander::Helpers

unless $0 == __FILE__  # for rackup
  Jekyll_commander = Rack::Builder.new { run Sinatra::Application }.to_app
end
