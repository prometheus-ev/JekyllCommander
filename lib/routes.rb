module JekyllCommander

  module Routes

    extend Sinatra::Delegator

    before do
      unless pass?
        ensure_repo
        get_files

        # default content-type
        content_type :xhtml
      end
    end

    get '' do
      redirect root_url
    end

    post '/markitup/preview_:type' do
      preview_for(params[:data], params[:type])
    end

    get '/*;new_:type' do
      begin
        erb :"new_#{params[:type]}"
      rescue Errno::ENOENT
        flash :error => "Type `#{params[:type]}' not supported yet."
        erb :index
      end
    end

    get '/*;status' do
      @status = status_for(path_info)
      erb :status
    end

    get '/*;log' do
      get_logs(@real_path)
      erb :log
    end

    get '/*;diff' do
      @sha = params[:sha]
      @diff = annotated_diff(@real_path, @sha)

      unless @diff.empty?
        erb :diff
      else
        flash :notice => "File `#{@base}' unchanged..."
        redirect url_for_file(path_info)
      end
    end

    get '/*;revert' do
      git.revert(@real_path)

      flash :notice => "Changes on `#{@base}' successfully reverted."
      redirect url_for_file(path_info)
    end

    get '/*;add' do
      git.add(@real_path)

      flash :notice => "File `#{@base}' successfully added."
      redirect url_for_file(path_info)
    end

    get %r{/.*;(?:site|staging|preview(?:_series)?)} do
      preview_folder || preview_page || file_not_found
    end

    post '/;update' do
      pull or return

      flash :notice => "Copy of `#{repo_name}' successfully updated."
      redirect root_url
    end

    get '/;save' do
      check_conflict and return

      @diff_total, @diff_stats = git.diff_stats

      if dirty?
        @msg = params[:msg]

        chdir(@real_path)
        erb :save
      else
        flash :error => 'Sorry, nothing to save yet...'
        redirect root_url(';status')
      end
    end

    post '/;save' do
      msg = params[:msg]

      if msg.is_a?(String) && msg.length > 12
        if pull && git.commit_all(msg) && git.push
          flash :notice => 'Site successfully updated.'
        else
          flash :error => 'An error occurred while trying to save your changes...'
        end

        redirect root_url
      else
        flash :error => "Required parameter `commit message' is missing or too short!"
        redirect root_url(';save')
      end
    end

    get '/;publish' do
      if publish?
        flash :notice => 'NOTE: You have unsaved changes...' if dirty?
        erb :publish
      else
        redirect root_url(';save')
      end
    end

    post '/;publish' do
      publish(params[:tag])

      if settings.site
        redirect settings.site
      else
        flash :notice => 'Site successfully published.'
        redirect root_url
      end
    end

    get '/*;search' do
      matches = search(params[:term], params[:type]) || []

      content_type 'application/json'
      matches[0, 15].sort.to_json
    end

    post '/*;search' do
      @query, @query_type = params[:query], params[:type]
      @matches = search(@query, @query_type) || []

      erb :search
    end

    get '/*;show' do
      pass unless @file

      content_type ContentType.of(@real_path)
      File.read(@real_path)
    end

    get '/*;edit' do
      render_page || file_not_found
    end

    get '/*;*' do
      not_found
    end

    get '/*' do
      pass if pass?
      render_folder || render_page || file_not_found
    end

    post '/*' do
      if @dir
        send("create_#{params[:type]}")
      else
        flash :error => "No such folder `#{@base}'."
        redirect root_url
      end
    end

    put '/*' do
      return erb(:index) unless page
      return update_file(params) if binary?

      write_series_images(Series::IMAGES.map { |img|
        params.delete(img)
      }.compact, pwd) if series?

      if page.update(real_params, Page.lang(path_info))
        name = page.filename

        if page.write!(git)
          flash :notice => "Page `#{name}' successfully updated."

          if name != @base
            delete_page(name)  # delete old page, redirect to new one
            return
          end
        else
          flash :error => "Unable to write page `#{name}'."
        end
      else
        flash :error => page.errors
      end

      erb :edit
    end

    delete '/*' do
      if @dir
        delete_folder
      elsif @file
        binary? ? delete_file : delete_page
      else
        not_found
      end
    end

    def file_not_found
      flash :error => "File not found `#{@base}'."
      redirect root_url
    end

    def preview_folder
      preview(path_info, @action) if @dir
    end

    def preview_page
      return unless @file
      return redirect(relative_url) unless page

      series = page.number if @action == 'preview_series'

      path = series ? root_path : relative_path(page.slug)
      path = [page.lang, path] if page.multilang?

      preview(path, *series ? [:preview, series] : [@action])
    end

    def render_folder
      return unless @dir

      chdir(@real_path)
      erb :index
    end

    def render_page
      return unless @file

      chdir(File.dirname(@real_path))

      return erb(:edit_file) if binary?
      return erb(:index) unless page

      flash :error => 'NOTE: This page has conflicts!!' if conflict?(@real_path)
      erb :edit
    end

    def create_folder
      if path = write_folder(params[:name])
        redirect url_for(path)
      end

      erb :new_folder
    end

    def create_page
      @page = Page.new(repo_root, path_info, params[:title], [
        [:multilang, !params[:multilang].nil?],
        [:render,    !params[:render].nil?],
        [:markup,    params[:markup]],
        [:layout,    params[:layout] || 'default']
      ])

      write_page
    end

    def create_post
      @page = Post.new(repo_root, path_info, params[:title], [
        [:multilang, !params[:multilang].nil?],
        [:render,    true],
        [:markup,    params[:markup]],
        [:layout,    params[:layout] || 'post'],
        [:author,    params[:author]],
        [:date,      params[:date] || Time.now.strftime("%Y-%m-%d")]
      ])

      write_page('post')
    end

    def create_series
      if params[:number] =~ Series::NUMBER_RE and week = $1 and year = $2
        year_path = write_folder(year, '/series', false)
        week_path = write_folder(week, year_path, false)

        chdir(week_path)
      else
        flash :error => "Required parameter `number' is invalid!"
      end

      @page = Series.new(repo_root, week_path, params[:title], [
        [:markup,    params[:markup]],
        [:layout,    params[:layout] || 'series'],
        [:author,    params[:author]],
        [:date,      params[:date] || Time.now.strftime("%Y/%m/%d")]
      ]) if week_path

      write_page('series')
    end

    def create_file
      if params[:file] && (filename = params[:file][:filename]) && (tempfile = params[:file][:tempfile])
        write_upload_file(tempfile, @real_path, filename)
        redirect relative_url(filename)
      else
        flash :error => 'No file selected!'
        erb :new_file
      end
    end

    def update_file(params)
      if @file
        if params[:file_name] && !(filename = File.basename(params[:file_name])).empty?
          if git.mv(@real_path, File.join(pwd, filename))
            flash :notice => "File successfully renamed: `#{@file}' -> `#{filename}'"
            redirect relative_url(filename)
          else
            flash :error => "Unable to rename file `#{@file}'."
          end
        end
      else
        flash :error => 'No file to change.'
      end

      erb :edit_file
    end

    def delete_folder
      git.rm(@real_path, :ignore_unmatch => true, :recursive => true)
      FileUtils.rm_r(@real_path) if File.exist?(@real_path)

      flash :notice => "Folder `#{@base}' successfully deleted."
      redirect relative_url('..')
    end

    def delete_page(new_name = nil)
      if page = new_name ? load_page : page()
        if page.destroy(git)
          action = new_name ? 'renamed' : 'deleted'
          flash :notice => "Page `#{@base}' successfully #{action}."

          redirect relative_url(*Array(new_name))
          return
        else
          flash :error => page.errors
        end
      end

      erb :index
    end

    def delete_file
      git.rm(@real_path, :ignore_unmatch => true)
      FileUtils.rm_f(@real_path) if File.exist?(@real_path)

      flash :notice => "File `#{@base}' successfully deleted."
      redirect relative_url
    end

  end

end
