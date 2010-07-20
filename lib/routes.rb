before do
  ensure_repo
  get_files

  @path      = request.path_info.sub(/(?:;|%3B).*/, '')
  @real_path = real_path(@path)

  @file = File.basename(@path) if File.file?(@real_path)
end

get '' do
  redirect url_for('/')
end

get '/*;new_:type' do
  erb :"new_#{params[:type]}"
end

get '/*;status' do
  @status, status = {}, git.status

  re = %r{\A#{Regexp.escape(splat)}(.*)}

  %w[added changed deleted untracked].each { |type|
    @status[type] = status.send(type).map { |path, _| path[re, 1] }.compact
  }

  erb :status
end

get '/*;revert' do
  git.lib.reset_file(nil, :path_limiter => @real_path, :quiet => true)
  git.checkout_index(:path_limiter => @real_path, :index => true, :force => true)

  redirect url_for_file(splat)
end

get '/*;add' do
  git.add(@real_path)
  redirect url_for_file(splat)
end

get '/;save' do
  @diff_stats = git.lib.diff_index_stats
  @diff_total = @diff_stats[:total]

  unless @diff_total[:files].zero?
    @msg = params[:msg]

    chdir(@real_path)
    erb :save
  else
    flash :error => 'Sorry, nothing to save yet...'
    redirect url_for('/' + u(';status'))
  end
end

post '/;save' do
  @msg = params[:msg]

  if @msg.is_a?(String) && @msg.length > 12
    git.commit(@msg.gsub(/'/, '´'))

    # TODO: git push (=> build _site, ...)
    sleep 3  # ???

    flash :notice => 'Site successfully updated.'
    redirect url_for('/')
  else
    flash :error => "Required parameter `commit message' is missing or too short!"
    redirect url_for('/' + u(';save'))
  end
end

get '/;publish' do
  @tags = git.tags.reverse

  unless @tags.empty?
    @logs = git.log(99).between(@tags.first)
    erb :publish
  else
    redirect url_for('/' + u(';save'))
  end
end

post '/;publish' do
  tag = params[:tag]

  if tag == '_new'
    tag = "jc-#{Time.now.to_f}"
    git.add_tag(tag)
  end

  # TODO: git push (=> build _site, ...)
  sleep 3  # ???

  redirect options.site || url_for('/')
end

get '/*;*' do
  not_found
end

get '/*' do
  render_folder || render_page || begin
    flash :error => "File not found `#{@real_path}'."
    redirect url_for('/')
  end
end

post '/*' do
  if File.directory?(@real_path)
    send("create_#{params[:type]}")
  else
    flash :error => "No such folder `#{@real_path}'."
    redirect url_for('/')
  end
end

put '/*' do
  if @page = Page.load(@real_path)
    attributes = params.reject { |key, _| key == '_method' || key == 'splat' }

    if @page.update(attributes, Page.lang(@path))
      if @page.write!(git)
        flash :notice => 'Page successfully updated.'
      else
        flash :error => "Unable to write file `#{@real_path}'."
      end
    else
      flash :error => @page.errors
    end

    erb :edit
  else
    flash :error => "Unable to load file `#{@real_path}'."
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
  erb :index
end

def render_page
  return unless File.file?(@real_path)

  chdir(File.dirname(@real_path))

  if @page = Page.load(@real_path)
    erb :edit
  else
    flash :error => "Unable to load file `#{@real_path}'."
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
      flash :error => "Folder `#{real_path}' already exists."
    end
  else
    flash :error => "Required parameter `name' is missing!"
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

  if @page.write(git)
    flash :notice => 'Page successfully created.'
    redirect relative_url(@page.filename)
  else
    flash :error => @page.errors
    get_files

    erb :new_page
  end
end

def delete_folder
  git.remove(@real_path, :recursive => true) rescue nil
  FileUtils.rm_r(@real_path) if File.exist?(@real_path)

  redirect relative_url('..')
end

def delete_page
  if page = Page.load(@real_path)
    if page.destroy(git)
      redirect relative_url
      return
    else
      flash :error => page.errors
    end
  else
    flash :error => "Unable to load file `#{@real_path}'."
  end

  erb :index
end
