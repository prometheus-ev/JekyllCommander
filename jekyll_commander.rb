require 'rubygems'
require 'nuggets/util/i18n'
require 'grit'
require 'sinatra'

INVISIBLE   = %w{. .git .gitignore _site}

enable :sessions

require 'lib/page'
require 'lib/helpers'
require 'lib/partials'

require 'lib/routes'

configure :development do
  set :jekyll_root, '/path/to/our/homepage'
  set :preview    , 'http://0.0.0.0'
  set :self_url   , 'http://0.0.0.0:4567'
end


before do
  chdir(session[:pwd] || options.jekyll_root)
  # $git = Grit::Repo.new(options.jekyll_root)
  # $git_actor = Grit::Actor.new('Arne Eilermann', 'eilermann@lavabit.com') # TODO: Have to feet this with login information!
  files_of
end

require 'lib/routes'
