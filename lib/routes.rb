require 'maruku'
require 'redcloth'
require 'nuggets/util/content_type'

module JekyllCommander

  module Routes

    before do
      ensure_repo
      get_files

      # default content-type
      content_type :xhtml
    end

    get '' do
      redirect root_url
    end

    get '/*;show' do
      pass unless @file

      content_type ContentType.of(@real_path)
      File.read(@real_path)
    end

    post '/markitup/preview_:type' do
      preview_for(params[:data], params[:type])
    end

    get '/markitup/*' do
      not_found
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

    get '/*;diff' do
      unless (@diff = annotated_diff(@real_path)).empty?
        erb :diff
      else
        flash :notice => "File `#{@base}' unchanged..."
        redirect url_for_file(path_info)
      end
    end

    get '/*;revert' do
      revert(@real_path)

      flash :notice => "Changes on `#{@base}' successfully reverted."
      redirect url_for_file(path_info)
    end

    get '/*;add' do
      git.add(@real_path)

      flash :notice => "File `#{@base}' successfully added."
      redirect url_for_file(path_info)
    end

    get %r{/.*;(?:site|staging|preview)} do
      preview_folder || preview_page || file_not_found
    end

    post '/;update' do
      pull or return

      flash :notice => "Copy of `#{repo_name}' successfully updated."
      redirect root_url
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
        redirect root_url(';status')
      end
    end

    post '/;save' do
      @msg = params[:msg]

      if @msg.is_a?(String) && @msg.length > 12
        commit(@msg) or return

        flash :notice => 'Site successfully updated.'
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

      if options.site
        redirect options.site
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

    get '/*;*' do
      not_found
    end

    get '/*' do
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
      return update_file(params) unless text?(@real_path)

      if page.type == :series
        files = Series::IMAGES.map { |img| params.delete("#{img}") }.compact
        # Why, Array#select does't want to do the job above?
        write_series_images(files, pwd, git)
      end

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
      elsif @file && text?(@real_path)
        delete_page
      elsif @file
        delete_file(@real_path, git)
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

      path = relative_path(page.slug)
      path = [page.lang, path] if page.multilang?

      preview(path, @action)
    end

    def render_folder
      return unless @dir

      chdir(@real_path)
      erb :index
    end

    def render_page
      return unless @file

      chdir(File.dirname(@real_path))

      return erb (:edit_file) unless text?(@real_path)
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
        write_upload_file(tempfile, @real_path, filename, git)
        redirect relative_url(filename)
      else
        flash :error => "No file selected!"
        erb :new_file
      end
    end

    def update_file(params)
      if @file
        if params[:file_name] && !(filename = File.basename(params[:file_name])).empty?
          if begin git.lib.mv(@real_path, File.join(pwd, filename)) rescue nil end
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
      git.remove(@real_path, :recursive => true) rescue nil
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

    def delete_file(path, git = nil)
      git.remove(path) rescue nil if git # TODO: Dear Arne, don't forget to DRY this up! Cheers, Arne
      if File.exist?(path)
        flash :error => "Unable to delete file `#{path}'."
        redirect relative_url(@file)
      else
        flash :notice => "File `#{@file}' successfully deleted."
        redirect relative_url
      end
    end

  end

end
