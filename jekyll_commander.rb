#! /usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'yaml'

gem 'blackwinter-git'

DEFAULT_OPTIONS = {
  :sessions => true,            # enable/disable cookie based sessions
  :logger   => nil,             # set Logger instance, or false
  :repo     => nil,             # set Git repo URL (required)
  :site     => nil,             # set site URL
  :staging  => nil,             # set staging URL
  :preview  => nil,             # set per-user preview URL
  :email    => '%s@localhost',  # set user's e-mail address (used for Git)

  # set temporary directory for Git repo clones
  :tmpdir => File.expand_path('../tmp', __FILE__),

  # set list of files to ignore
  :ignore => %w[
    . .. .git .gitignore
    _site _site.tmp _site.old
    _plugins favicon.ico
  ]
}

cfg = File.expand_path('../config.yaml', __FILE__)
opt = File.readable?(cfg) ? YAML.load_file(cfg) : {}

abort 'No repo to serve!' unless opt[:repo]

configure { set DEFAULT_OPTIONS.merge(opt) }

configure :development do
  require 'logger'
  set :logger, Logger.new(STDOUT)
end if opt[:logger].nil?

%w[page helpers routes].each { |lib| require "lib/#{lib}" }

include JekyllCommander::Routes
helpers JekyllCommander::Helpers

unless $0 == __FILE__  # for rackup
  Jekyll_commander = Rack::Builder.new { run Sinatra::Application }.to_app
end
