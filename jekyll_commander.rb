#! /usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'yaml'

DEFAULT_OPTIONS = {
  :sessions => true,
  :repo     => nil,
  :email    => '%s@localhost',
  :tmpdir   => File.expand_path('../tmp', __FILE__),
  :ignore   => %w[. .. .git .gitignore _site _plugins favicon.ico],
  :preview  => nil
}

configure do
  cfg = File.expand_path('../config.yaml', __FILE__)
  opt = File.readable?(cfg) ? YAML.load_file(cfg) : {}

  abort 'No repo to serve!' unless opt[:repo]

  DEFAULT_OPTIONS.merge(opt).each { |key, value| set key, value }
end

require 'lib/page'
require 'lib/helpers'
require 'lib/partials'
require 'lib/routes'

unless $0 == __FILE__  # for rackup
  Jekyll_commander = Rack::Builder.new { run Sinatra::Application }.to_app
end
