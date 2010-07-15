#! /usr/bin/ruby

require 'rubygems'
require 'sinatra'
require 'grit'

IGNORE = %w[. .. .git .gitignore _site]

enable :sessions

require 'lib/page'
require 'lib/helpers'
require 'lib/partials'
require 'lib/routes'

configure do
  set :jekyll_root, File.expand_path('../../prometheus_homepage', __FILE__)
  set :preview, 'http://localhost/preview'
end

before do
  #$git = Grit::Repo.new(options.jekyll_root)
  #$git_actor = Grit::Actor.new('Arne Eilermann', 'eilermann@lavabit.com') # TODO: Have to feed this with login information!

  get_files
end

unless $0 == __FILE__  # for rackup
  Jekyll_commander = Rack::Builder.new { run Sinatra::Application }.to_app
end
