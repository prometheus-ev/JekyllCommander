get '/' do
  erb :index
end

######################################################################
# Page routes                                                        #
######################################################################

post '/page' do
  options = {
    :multilang => !params[:multilang].nil?,
    :render    => !params[:render].nil?,
    :markup    => params[:markup]
  }

  @page = Page.new(params[:title], options)

  if @page.render?
    @page.header[:layout] = 'default' # TODO: Should be continued
  end

  if @page.valid? && @page.write
    session[:flash] = 'Page successfully created.'
    files_of
    @lang = Page.languages.first
    @filename = @page.filename(@lang)
    erb :edit
  else
    session[:flash] = @page.errors.join("<br />\n")
    files_of
    erb :new_page
  end
end

put '/page' do
  # TODO: Insert code here!
  @filename = params[:filename]
  if @page = Page.load(File.join($pwd, @filename))
    if lang = lang_from_filename(@filename)
      @lang = lang
    else
      @lang = Page.languages.first
    end
    attributes = params.delete_if { |k, _| k == '_method' || k == 'filename' }
    if new_page = @page.update(attributes, @lang)
      @page = new_page
      session[:flash] = 'Successfully updated.' if @page.write!
    else
      session[:flash] = new_page.errors.join("<br />\n")
    end
    erb :edit
  else
    session[:flash] = 'Unable to load file.'
    erb :index
  end
end

delete '/page' do
  path = File.join($pwd, params[:filename])
  if page = Page.load(path)
    session[:flash] = page.errors.join("<br />\n") unless page.destroy
  else
    session[:flash] = 'Unable to load file.'
  end
  files_of
  erb :index
end

get '/edit/:filename' do
  @filename = params[:filename]
  if @page = Page.load(File.join($pwd, @filename))
    if lang = lang_from_filename(@filename)
      @lang = lang
    else
      @lang = Page.languages.first
    end
    erb :edit
  else
    session[:flash] = 'Unable to load file.'
    erb :index
  end
end

######################################################################
# Directory routes                                                   #
######################################################################

get '/chdir/:dir' do
  if params[:dir] == '__up'
    dir = $pwd == options.jekyll_root ? $pwd : $pwd.match(/(^.+)\/.+$/)[1]
  else
    dir = File.join($pwd, params[:dir])
  end
  files_of if chdir(dir)
  erb :index
end

get '/new/:file_type' do
  erb params[:file_type] == 'page' ? :new_page : :new_folder
end

post '/folder' do
  if params[:name].nil? || params[:name].empty?
    session[:flash] = 'You have to name it!'
    erb :new_folder
  elsif File.exist?(path = File.join($pwd, params[:name]))
    session[:flash] = "A file named <em>#{params[:name]}</em> already exists."
    erb :new_folder
  else
    chdir(path) if Dir.mkdir(path)
    files_of
    erb :index
  end
end
