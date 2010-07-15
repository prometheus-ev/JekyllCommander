before do
  @path      = request.path_info
  @real_path = real_path(@path)

  @file = File.basename(@path) if File.file?(@real_path)
end

get '' do
  redirect url_for('/')
end

get '/*;new_:type' do
  erb :"new_#{params[:type]}"
end

get '/*' do
  render_folder || render_page || begin
    flash :error => 'File not found.'
    redirect url_for('/')
  end
end

post '/*' do
  if File.directory?(@real_path)
    send("create_#{params[:type]}")
  else
    flash :error => 'No such folder.'
    redirect url_for('/')
  end
end

put '/*' do
  if @page = Page.load(@real_path)
    attributes = params.reject { |key, _| key == '_method' || key == 'splat' }

    if @page.update(attributes, Page.lang(@path))
      flash :notice => 'Successfully updated.' if @page.write!
    else
      flash :error => @page.errors
    end

    erb :edit
  else
    flash :error => 'Unable to load file.'
    erb :index
  end
end

delete '/*' do
  if File.directory?(@real_path)
    delete_folder
  elsif File.file?(@real_path)
    delete_page
  end
end

def render_folder
  return unless File.directory?(@real_path)

  chdir(@real_path)
  get_files

  erb :index
end

def render_page
  return unless File.file?(@real_path)

  chdir(File.dirname(@real_path))
  get_files

  if @page = Page.load(@real_path)
    erb :edit
  else
    flash :error => 'Unable to load file.'
    erb :index
  end
end

def create_folder
  name = params[:name]

  unless name.nil? || name.empty?
    path = File.join(@path, name)
    real_path = real_path(path)

    unless File.exist?(real_path)
      Dir.mkdir(real_path)
      redirect url_for(path)

      return
    else
      flash :error => 'Already exists.'
    end
  else
    flash :error => 'You have to name it!'
  end

  erb :new_folder
end

def create_page
  @page = Page.new(@real_path, params[:title], [
    [:multilang, !params[:multilang].nil?],
    [:render,    !params[:render].nil?],
    [:markup,    params[:markup]],
    [:layout,    params[:layout] || 'default']
  ])

  if @page.write
    flash :notice => 'Page successfully created.'
    redirect relative_url(@page.filename)
  else
    flash :error => @page.errors
    get_files

    erb :new_page
  end
end

def delete_folder
  FileUtils.rm_r(@real_path)
  redirect relative_url('..')
end

def delete_page
  if page = Page.load(@real_path)
    if page.destroy
      redirect relative_url
      return
    else
      flash :error => page.errors
    end
  else
    flash :error => 'Unable to load file.'
  end

  erb :index
end
