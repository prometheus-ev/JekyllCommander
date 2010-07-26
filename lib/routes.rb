module JekyllCommander; module Routes

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
    @status, status = { 'conflict' => conflicts }, git.status

    re = %r{\A#{Regexp.escape(@path.sub(/\A\//, ''))}(.*)}

    %w[added changed deleted untracked].each { |type|
      @status[type] = status.send(type).map { |path, _| path[re, 1] }.compact
    }

    erb :status
  end

  get '/*;diff' do
    @diff = git.diff.path(@real_path).patch.split("\n").map { |row|
      [case row
         when /\A(?:diff|index)\s/  then :preamble
         when /\A(?:new|deleted)\s/ then :preamble
         when /\A(?:---|\+\+\+)\s/  then :preamble
         when /\A@@\s/              then :hunk
         when /\A-/                 then :deletion
         when /\A\+/                then :insertion
         else                            :context
       end, h(row).sub(/\A\s+/) { |m| '&nbsp;' * m.length }.
                   sub(/\s+\z/) { |m| %Q{<span class="trailing_space">#{'&nbsp;' * m.length}</span>} }]
    }

    unless @diff.empty?
      erb :diff
    else
      flash :notice => 'File unchanged...'
      redirect url_for_file(@path)
    end
  end

  get '/*;revert' do
    git.reset(nil, :path_limiter => @real_path, :quiet => true)
    git.checkout_index(:path_limiter => @real_path, :index => true, :force => true)

    flash :notice => 'Change successfully reverted.'
    redirect url_for_file(@path)
  end

  get '/*;add' do
    git.add(@real_path)

    flash :notice => 'File successfully added.'
    redirect url_for_file(@path)
  end

  get '/*;preview' do
    if options.preview
      if page = Page.load(@real_path)
        Dir.chdir(repo_root) { system('rake') }  # TODO: error handling!

        path = relative_path(page.slug)
        path = [page.lang, path] if page.multilang?
        redirect File.join(options.preview, path)

        return
      else
        flash :error => "Unable to load page `#{@real_path}'."
      end
    else
      flash :error => "Option `preview' not set..."
    end

    redirect url_for_file(@path)
  end

  get '/;save' do
    check_conflict and return

    @diff_stats = git.diff.index_stats
    @diff_total = @diff_stats[:total]

    if dirty?
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
      pull or return

      git.commit_all(@msg)
      git.push  # TODO: handle non-fast-forward?

      flash :notice => 'Site successfully updated.'
      redirect url_for('/')
    else
      flash :error => "Required parameter `commit message' is missing or too short!"
      redirect url_for('/' + u(';save'))
    end
  end

  get '/;publish' do
    git.fetch

    @tags = git.tags.reverse
    @logs = git.log(99)
    @logs.between(@tags.first) unless @tags.empty?

    unless @logs.empty? && @tags.empty?
      flash :notice => 'NOTE: You have unsaved changes...' if dirty?
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
    else
      # delete tag so we can re-push it
      git.push('origin', ":#{tag}")
    end

    git.push('origin', tag)

    if options.site
      redirect options.site
    else
      flash :notice => 'Site successfully published.'
      redirect url_for('/')
    end
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
      if @page.update(real_params, Page.lang(@path))
        if @page.write!(git)
          flash :notice => 'Page successfully updated.'
        else
          flash :error => "Unable to write page `#{@real_path}'."
        end
      else
        flash :error => @page.errors
      end

      erb :edit
    else
      flash :error => "Unable to load page `#{@real_path}'."
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
      flash :error => 'NOTE: This page has conflicts!!' if conflict?(@real_path)
      erb :edit
    else
      flash :error => "Unable to load page `#{@real_path}'."
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

        flash :notice => 'Folder successfully created.'
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

    flash :notice => 'Folder successfully deleted.'
    redirect relative_url('..')
  end

  def delete_page
    if page = Page.load(@real_path)
      if page.destroy(git)
        flash :notice => 'Page successfully deleted.'
        redirect relative_url

        return
      else
        flash :error => page.errors
      end
    else
      flash :error => "Unable to load page `#{@real_path}'."
    end

    erb :index
  end

end; end
