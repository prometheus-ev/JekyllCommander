module JekyllCommander

  module Helpers

    include ERB::Util

    PATH_INFO_RE = %r{(.*)(?:;|%3B)(.*)}i

    UPCASE_RE    = %r{\b(?:html|xml|url)\b}i

    PASS_RE      = %r{\A/(?:__sinatra__|markitup)/}

    class ::String

      def humanize
        ActiveSupport::Inflector.humanize(self).gsub(UPCASE_RE) { |m| m.upcase }
      end

    end

    def u2(path)
      path.split('/').map { |dir| u(dir) }.join('/')
    end

    def partial(page, options = {})
      erb :"_#{page}", options.merge(:layout => false)
    end

    def form(method = :post, url = relative_path, file_upload = false)
      unless %w[get post].include?(method.to_s)
        method_override, method = method, :post
      end

      form = %Q{<form action="#{url_for(url)}" method="#{method}"} +
        %Q{#{' enctype="multipart/form-data"' if file_upload}>}
      form << %Q{\n<input type="hidden" name="_method" value="#{method_override}" />} if method_override
      form
    end

    def form_this(method = :post)
      form(method, request_info)
    end

    def form_new(type, file_upload = false)
      form(:post, relative_path, file_upload) +
        %Q{\n<input type="hidden" name="type" value="#{type}" />}
    end

    def form_delete(text, url = relative_path)
      text = "Delete #{text}" if text.is_a?(Symbol)
      onclick = %q{onclick='if(!confirm("Are your sure?"))return false;'}
      form(:delete, url) + %Q{\n<p><input type="submit" value="#{text}" #{onclick} /></p>\n</form>}
    end

    def images_and_descriptions_fields(descriptions = [])
      out = ''

      Series::IMAGES.each { |img|
        out << %Q{<p><label for="file_#{img}">Select image ("#{name = img.sub(/.jpg\z/, '')}"):}
        out << series_image_check(File.join(pwd, img)) + '</label><br />'
        out << %Q{<input type="file" name="#{img}" id="file_#{img}" /></p>\n}

        unless img == 'start.jpg'
          out << %Q{<p><label for="desc_#{img}">Description for image ("#{name}"):</label><br />\n}
          out << %Q{<input type="text" name="header[descriptions[#{img_index = name.to_i - 1}]]" id="desc_#{img}" }
          out << %Q{value="#{h(descriptions[img_index]) || ''}" size="50" /></p>\n}
        end
      }

      return out
    end

    def html_tag(tag, content = nil, html_options = {})
      attributes = html_options.map { |k, v| %Q{#{k}="#{h(v)}"} }.join(' ')
      "<#{tag}#{" #{attributes}" unless attributes.empty?}>#{content}</#{tag}>"
    end

    def image_tag(path, html_options = {})
      html_tag(:img, nil, html_options.merge(:src => url_for("/images/#{path}")))
    end

    def url_for(path)
      path.start_with?('/') ? "#{request.script_name}#{path}".gsub(%r{/+}, '/') : path
    end

    def url_for_file(file)
      url_for(path_for_file(file))
    end

    def path_for_file(*file)
      File.expand_path(u2(File.join('/', file)), '/')
    end

    def link_to(name, url, html_options = {})
      html_tag(:a, name, html_options.merge(:href => url_for(url)))
    end

    def link_to_file(file, name = file)
      path, url = File.join(pwd, file), relative_path(file)

      if File.directory?(path)
        link_to("#{name}/", url)
      elsif File.file?(path)
        link_to(name, url)
      else
        "#{name}?"
      end
    end

    def link_to_action(action, file, url = nil)
      link_to(action.capitalize, url || relative_path("#{file};#{action}"))
    end

    def language_links(page, current_lang = page.lang)
      Page::LANGUAGES.map { |lang|
        if lang == current_lang
          "<strong>#{lang.upcase}</strong>"
        else
          link_to_file(page.filename(lang), lang.upcase)
        end
      }.join(" |\n")
    end

    def link_to_site(name = 'Site', html_options = {})
      link_to_preview(name, html_options.merge(:__type__ => :site))
    end

    def link_to_staging(name = 'Staging', html_options = {})
      link_to_preview(name, html_options.merge(:__type__ => :staging))
    end

    def link_to_preview(name = 'Preview', html_options = {})
      type = html_options.delete(:__type__) || :preview
      return unless options.send(type)

      img = image_tag("#{type}.png", :alt => type)

      link_to(img, relative_path("#{@file};#{type}"), {
        :title  => name,
        :target => '_blank'
      }.merge(html_options))
    end

    def link_to_user(name = user, html_options = {})
      link = user_config[:link]
      link ? link_to(name, link, html_options) : name
    end

    def flash(hash)
      session[:flash] = {} unless session[:flash].is_a?(Hash)
      flash = session[:flash]

      hash.each { |key, value|
        flash[key] = [flash[key], value].map { |v|
          v ? v.is_a?(Array) ? v : [v] : []
        }.inject { |a, b| a.concat(b) }
      }

      flash
    end

    def render_flash(*keys)
      return unless flash = session[:flash]

      keys.map { |key|
        Array(flash.delete(key)).map { |f| %Q{<p class="#{key}">#{h(f)}</p>} }
      }.flatten.join("\n")
    end

    def header_fields(hash)
      hash.sort_by { |key, _| key.to_s }.map { |key, value|
        renderer = "render_#{key}_header"
        renderer = :render_header_field unless respond_to?(renderer)

        %Q{<p>
          <label for="page_#{key}">#{key.to_s.humanize}</label>:<br />
          #{send(renderer, key, value)}
        </p>}
      }.join if hash.is_a?(Hash)
    end

    def render_header_field(key, value)
      name, id = "header[#{key}]", "page_#{key}"

      case value
        when Array
          %Q{<textarea name="#{name}" id="#{id}" rows="4" cols="44">#{h(value.join("\r\n"))}</textarea>}
        else
          %Q{<input type="text" name="#{name}" id="#{id}" value="#{h(value)}" size="50" />}
      end
    end

    def render_layout_header(key = :layout, value = 'default')
      select = %Q{<select name="#{key}" id="page_#{key}">}

      layouts = Dir[File.join(repo_root, '_layouts', '*.html')]
      layouts.map! { |layout| File.basename(layout, '.html') }
      layouts.sort!

      layouts.unshift('').each { |layout|
        select << %Q{\n<option value="#{layout}"#{' selected="selected"' if layout == value}>#{layout.humanize}</option>}
      }

      select << "\n</select>"
    end

    def markup_links
      Page::MARKUP_LINKS[@page.markup.to_sym].map { |name, link|
        %Q{<a href="#{link}" target="_blank">#{name}</a>}
      }.join(' | ')
    end

    def options_for_markup_select(current = Page::DEFAULT_MARKUP)
      select = %Q{<select name="markup" id="page_markup">}

      Page::MARKUPS.each { |markup|
        select << %Q{\n<option value="#{markup}"#{' selected="selected"' if markup == current}>#{markup.humanize}</option>}
      }

      select << "\n</select>"
    end

    def options_for_series_number_select(current = 1.week.from_now.at_beginning_of_week)
      select = %Q{<select name="number" id="page_number">}

      -1.upto(52) { |i|
        date = current + i.weeks

        value = '%02d/%d' % %w[%V %G].map { |f| date.strftime(f).to_i }
        range = [date, date.at_end_of_week].map { |d| d.strftime('%b %d %Y') }.join(' - ')

        select << %Q{\n<option value="#{value}"#{' selected="selected"' if i.zero?}>#{value} (#{range})</option>}
      }

      select << "\n</select>"
    end

    def request_info
      @request_info ||= request.path_info
    end

    def path_info
      @path_info ||= begin
        path_info = request_info
        path_info, @action = $1, $2 if path_info =~ PATH_INFO_RE

        @action ||= 'edit'

        @real_path = real_path(path_info)
        @base = File.basename(path_info)
        @type = Page.type(path_info)

        if File.directory?(@real_path)
          @dir  = @base
        elsif File.file?(@real_path)
          @file = @base
        end

        path_info
      end
    end

    def pwd
      @pwd ||= real_path(relative_pwd)
    end

    def relative_pwd
      @relative_pwd ||= begin
        _path_info = path_info  # populate ivars
        @dir ? _path_info : File.dirname(_path_info)
      end
    end

    def relative_path(*args)
      path_for_file(relative_pwd, *args)
    end

    def relative_url(*args)
      url_for(relative_path(*args))
    end

    def root_path(*args)
      path_for_file('/', *args)
    end

    def root_url(*args)
      url_for(root_path(*args))
    end

    def real_path(path)
      File.join(repo_root, path)
    end

    def path_re(path, optional_slash = false)
      %r{\A#{Regexp.escape(path.chomp('/'))}#{optional_slash ? '/?' : '(?:/|\z)'}}
    end

    def chdir(path)
      @pwd = @relative_pwd = nil
      get_files
      pwd
    end

    def get_files
      @files = Dir.entries(pwd).sort - options.ignore
    end

    def trail_links
      links, dirs = [], relative_pwd.split('/'); dirs.shift

      until dirs.empty?
        links.unshift(link_to(dirs.last, path_for_file(dirs)))
        dirs.pop
      end

      links.unshift(link_to('ROOT', '/'))
    end

    def file_links
      links = []
      links <<  'edit'              if @file
      links << ['show', @file_url]  if @file_url
      links.concat(%w[diff revert]) if dirty?(@real_path)

      links.map { |action, url|
        link_to_action(action, @file, url) unless action == @action
      }.compact
    end

    def status_links_for(file, type)
      links = %w[diff revert]

      case type
        when 'conflict'  then links.delete('revert')
        when 'untracked' then links = %w[add]
      end

      links.map { |action| link_to_action(action, file) }
    end

    def real_params
      if series? and descriptions = params[:header].delete('descriptions')
        params[:header][:descriptions] = descriptions.
          inject([]) { |a, (k, v)| a[k.to_i] = v; a }
      end

      @real_params ||= params.reject { |key, _|
        key == '_method' || key == 'splat'
      }
    end

    def user
      @user ||= request.env['REMOTE_USER'] || begin
        Etc.getpwuid(Process.euid).name
      rescue ArgumentError  # can't find user for xy
        ENV['USER'] || 'N.N.'
      end
    end

    def user_config
      @user_config ||= options.users && options.users[user] || {}
    end

    def user_name
      @user_name ||= user_config[:name] || user
    end

    def user_email
      @user_email ||= user_config[:email] || options.email % user
    end

    def repo_name
      @repo_name ||= File.basename(options.repo, Git::GIT_DIR)
    end

    def repo_root
      @repo_root ||= File.join(options.tmpdir, "#{repo_name}-#{u(user)}")
    end

    def git
      @git ||= Git.new(repo_root, options.logger) { |err|
        flash :error => "#{err}\n\n#{err.err}"
        nil
      }
    end

    def ensure_repo
      if git.exist?
        pull if pull?
      else
        git.clone(options.repo) { |config|
          config['user.name']  = user_name
          config['user.email'] = user_email

          config['core.sharedRepository'] = true

          rake
        }
      end
    end

    def pull?
      pulled, pulled_at = session[:pulled], session[:pulled_at]
      pulled != repo_root || !pulled_at || pulled_at < 12.hours.ago.utc
    end

    def pull
      saved = git.stash(:save, 'about to pull')

      if git.pull
        session[:pulled]    = repo_root
        session[:pulled_at] = Time.now.utc
      else
        failed = true
        redirect root_url
      end

      git.stash(:pop) if saved

      !failed && !check_conflict(true)
    end

    def dirty?(path = nil)
      if path || @diff_total.blank?
        !git.diff_index(path).empty?
      else
        @diff_total[:files] > 0
      end
    end

    def conflict?(path = nil)
      (@has_conflicts ||= {})[path] ||= git.conflicts(path).any?
    end

    def check_conflict(oops = false)
      if conflict?
        flash :error => "#{oops ? 'Oops, now' : 'Sorry,'} you have conflicts!!"
        redirect root_url(';status')

        true
      else
        false
      end
    end

    def status_for(path)
      (@status_for ||= {})[path] ||= git.status_for(path)
    end

    def status_summary(path = relative_pwd)
      status_for(path).sort.map { |type, files|
        %Q{<span class="#{type}">#{files.size}</span>}
      }.join('/')
    end

    def annotated_diff(path)
      git.diff(path).map { |line|
        type = case line
          when /\A(?:diff|index|new|deleted|[+-]{3})\s/ then :preamble
          when /\A@@\s/                                 then :hunk
          when /\A-/                                    then :deletion
          when /\A\+/                                   then :insertion
          else                                               :context
        end

        content = h(line)
        content.sub!(/\A\s+/) { |m| '&nbsp;' * m.length }
        content.sub!(/\s+\z/) { |m|
          %Q{<span class="trailing_space">#{'&nbsp;' * m.length}</span>}
        }

        [type, content]
      }
    end

    def publish?
      git.fetch

      @tags = git.tags
      @logs = git.log(['origin', @tags.empty? ? 'HEAD' : "#{@tags.first.name}.."])

      @logs.any? || @tags.any?
    end

    def publish(tag)
      if tag == '_new'
        git.tag(tag = "jc-#{Time.now.to_f}")
      else
        # delete tag so we can re-push it
        git.delete_tag(tag)
      end

      git.push
      git.push_tag(tag)
    end

    def rake(*args)
      # TODO: error handling!
      Dir.chdir(repo_root) { system('rake', *args) }
    end

    def preview(path, type = nil)
      target = options.send(type || :preview)

      if target
        if type.to_s == 'preview'
          rake
          target %= user
        end

        redirect File.join(target, path)
      else
        flash :error => "Option `#{type}' not set..."
        redirect url_for_file(path_info)
      end
    end

    def preview_for(data, type = nil)
      @_preview_template ||= File.read(
        File.join(settings.public, %w[markitup templates preview.html])
      )

      @_preview_template.sub(/<!-- content -->/, case type.to_s
        when 'textile'  then RedCloth.new(data).to_html
        when 'markdown' then Maruku.new(data).to_html
        else data
      end)
    end

    def search(query, type = :name)
      cmd, ignore, path_re = [], options.ignore, path_re(path = pwd)

      case type.to_s
        when 'name'
          cmd.concat(%W[find #{path} -regextype posix-egrep])
          ignore.each { |i| cmd.concat(%W[\( -path */#{i} -prune \) -o]) }
          cmd.concat(%W[\( -iregex .*/[^/]*#{query}[^/]* -print0 \)])
        when 'text'
          cmd.concat(%W[grep -E -e #{query} -i -l -s -Z -I -r])
          ignore.each { |i| cmd.concat(%W[--exclude-dir #{i} --exclude #{i}]) }
          cmd << path
        else
          flash :error => "Invalid type parameter `#{type}'."
          return
      end

      stdin, stdout, stderr = Open3.popen3(*cmd)
      stdout.read.split("\0").each { |path| path.sub!(path_re, '') }
    end

    def file_type
      @file_type ||= FileMagic.fm(:mime).file(@real_path)
    end

    def binary?
      defined?(@is_binary) ? @is_binary : @is_binary =
        [:file, :series].include?(Page.type(path_info)) && file_type !~ /\Atext\//
    end

    def series?
      defined?(@is_series) ? @is_series : @is_series =
        page.type == :series && path_info.count('/') > 3
    end

    def page
      defined?(@page) ? @page : @page = load_page
    end

    def load_page
      page = Page.load(repo_root, path_info)
      flash :error => "Unable to load page `#{@base}'." unless page

      page
    end

    def write_page(type = 'page')
      prefix = "#{type.humanize} `#{@base}'"

      if page && page.write(git)
        flash :notice => "#{prefix} successfully created."
        redirect url_for(File.join('/', page.base, page.filename))
      else
        flash :error => page ? page.errors : "#{prefix} could not be created."
        get_files

        erb "new_#{type}".to_sym
      end
    end

    def write_upload_file(tempfile, path, name)
      FileUtils.mv(tempfile.path, File.join(path, name))
      flash :notice => "File `#{name}' successfully written." if git.add(path)
    end

    def write_folder(name, path_info = path_info, warn_if_exists = true)
      unless name.blank?
        path = File.join(path_info, name)
        base = File.basename(path)
        real_path = real_path(path)

        unless File.exist?(real_path)
          Dir.mkdir(real_path)

          flash :notice => "Folder `#{base}' successfully created."

          return path
        else
          if warn_if_exists
            flash :error => "Folder `#{base}' already exists."
            return false
          else
            return path
          end
        end
      else
        flash :error => "Required parameter `name' is missing!"

        return false
      end
    end

    def write_series_images(files, path)
      files.each { |file|
        name, tempfile = file[:name], file[:tempfile].path

        if Series::IMAGES.include?(name) && (img = Magick::Image.read(tempfile)[0])
          if img.format != 'JPEG'
            flash :error => "Image `#{name}' has to be a JPEG!"
          elsif img.rows != img.columns
            flash :error => "Image `#{name}' has to be a square (like 120x120 px)!"
          else
            img.resize_to_fit!(name == 'start.jpg' ? 120 : 100)
            img.write(File.join(path, name))

            flash :notice => "File `#{name}' successfully written." if git.add(path)
          end

          img.destroy!
        else
          flash :error => "Could not read image `#{name}' is missing!"
        end
      }
    end

    def series_image_check(path)
      icon, alt = File.exists?(path) ? ['accept.png',      'Image available'] :
                                       ['exclamation.png', 'Image missing!']

      image_tag(icon, :alt => alt)
    end

    def pass?
      defined?(@pass) ? @pass : @pass = request_info =~ PASS_RE
    end

  end

end
