#! /usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'yaml'

gem 'blackwinter-git'

DEFAULT_OPTIONS = {
  :sessions => true,
  :repo     => nil,
  :site     => nil,
  :preview  => nil,
  :email    => '%s@localhost',
  :tmpdir   => File.expand_path('../tmp', __FILE__),
  :ignore   => %w[. .. .git .gitignore _site _plugins favicon.ico]
}

configure do
  cfg = File.expand_path('../config.yaml', __FILE__)
  opt = File.readable?(cfg) ? YAML.load_file(cfg) : {}

  abort 'No repo to serve!' unless opt[:repo]

  DEFAULT_OPTIONS.merge(opt).each { |key, value| set key, value }
end

%w[page helpers routes].each { |lib| require "lib/#{lib}" }

unless $0 == __FILE__  # for rackup
  Jekyll_commander = Rack::Builder.new { run Sinatra::Application }.to_app
end
