require 'maruku'
require 'redcloth'
require 'nuggets/util/content_type'

module JekyllCommander

  module Routes

    before do
      ensure_repo
      extract_path
      get_files
    end

    get '' do
      redirect url_for('/')
    end

    get '/files/*' do
      if @file
        content_type ContentType.of(@real_path)
        File.read(@real_path)
      else
        pass
      end
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
      @status = status_for(@path)
      erb :status
    end

    get '/*;diff' do
      unless (@diff = annotated_diff(@real_path)).empty?
        erb :diff
      else
        flash :notice => "File `#{@base}' unchanged..."
        redirect url_for_file(@path)
      end
    end

    get '/*;revert' do
      revert(@real_path)

      flash :notice => "Changes on `#{@base}' successfully reverted."
      redirect url_for_file(@path)
    end

    get '/*;add' do
      git.add(@real_path)

      flash :notice => "File `#{@base}' successfully added."
      redirect url_for_file(@path)
    end

    get %r{/.*;(?:site|staging|preview)} do
      preview_folder || preview_page || file_not_found
    end

    post '/;update' do
      pull or return

      flash :notice => "Copy of `#{repo_name}' successfully updated."
      redirect url_for('/')
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
        commit(@msg) or return

        flash :notice => 'Site successfully updated.'
        redirect url_for('/')
      else
        flash :error => "Required parameter `commit message' is missing or too short!"
        redirect url_for('/' + u(';save'))
      end
    end

    get '/;publish' do
      if publish?
        flash :notice => 'NOTE: You have unsaved changes...' if dirty?
        erb :publish
      else
        redirect url_for('/' + u(';save'))
      end
    end

    post '/;publish' do
      publish(params[:tag])

      if options.site
        redirect options.site
      else
        flash :notice => 'Site successfully published.'
        redirect url_for('/')
      end
    end

    get '/*;search' do
      matches = search(params[:term]) || []

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
        redirect url_for('/')
      end
    end

    put '/*' do
      return erb(:index) unless page

      if page.update(real_params, Page.lang(@path))
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
      @dir ? delete_folder : @file ? delete_page : not_found
    end

    def file_not_found
      flash :error => "File not found `#{@base}'."
      redirect url_for('/')
    end

    def preview_folder
      preview(@path, @action) if @dir
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

      return erb(:index) unless page

      flash :error => 'NOTE: This page has conflicts!!' if conflict?(@real_path)
      erb :edit
    end

    def create_folder
      name = params[:name]

      unless name.blank?
        path = File.join(@path, name)
        base = File.basename(path)
        real_path = real_path(path)

        unless File.exist?(real_path)
          Dir.mkdir(real_path)

          flash :notice => "Folder `#{base}' successfully created."
          redirect url_for(path)

          return
        else
          flash :error => "Folder `#{base}' already exists."
        end
      else
        flash :error => "Required parameter `name' is missing!"
      end

      erb :new_folder
    end

    def create_page
      @page = Page.new(repo_root, @path, params[:title], [
        [:multilang, !params[:multilang].nil?],
        [:render,    !params[:render].nil?],
        [:markup,    params[:markup]],
        [:layout,    params[:layout] || 'default']
      ])

      if page.write(git)
        flash :notice => "Page `#{@base}' successfully created."
        redirect relative_url(page.filename)
      else
        flash :error => page.errors
        get_files

        erb :new_page
      end
    end

    def delete_folder
      git.remove(@real_path, :recursive => true) rescue nil
      FileUtils.rm_r(@real_path) if File.exist?(@real_path)

      flash :notice => "Folder `#{@base}' successfully deleted."
      redirect relative_url('..')
    end

    def delete_page(new_name = nil)
      if page
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

  end

end
