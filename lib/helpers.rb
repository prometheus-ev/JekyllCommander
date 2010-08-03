require 'erb'
require 'git'
require 'active_support'

module JekyllCommander; module Helpers

  include ERB::Util

  UPCASE_RE = %r{\b(?:html|xml|url)\b}i

  class ::String
    def humanize
      super.gsub(UPCASE_RE) { |m| m.upcase }
    end
  end

  def u2(path)
    path.split('/').map { |dir| u(dir) }.join('/')
  end

  def partial(page, options = {})
    erb :"_#{page}", options.merge(:layout => false)
  end

  def form(method = :post, url = relative_path)
    unless %w[get post].include?(method.to_s)
      method_override, method = method, :post
    end

    form = %Q{<form action="#{url_for(url)}" method="#{method}">}
    form << %Q{\n<input type="hidden" name="_method" value="#{method_override}" />} if method_override
    form
  end

  def form_this(method = :post)
    form(method, request.path_info)
  end

  def form_new(type)
    form + %Q{\n<input type="hidden" name="type" value="#{type}" />}
  end

  def form_delete(text, url = relative_path)
    text = "Delete #{text}" if text.is_a?(Symbol)
    onclick = %q{onclick='if(!confirm("Are your sure?"))return false;'}
    form(:delete, url) + %Q{\n<p><input type="submit" value="#{text}" #{onclick} /></p>\n</form>}
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

  def flash(hash)
    session[:flash] = {} unless session[:flash].is_a?(Hash)
    flash = session[:flash]

    hash.each { |key, value|
      flash[key] = Array(flash[key]).flatten unless flash[key].is_a?(Array)
      flash[key].concat(Array(value).flatten)
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
        %Q{<textarea name="#{name}" id="#{id}" rows="4" cols="44">#{value.join("\r\n")}</textarea>}
      else
        %Q{<input type="text" name="#{name}" id="#{id}" value="#{value}" size="50" />}
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

  def path_re(path, optional_slash = false)
    %r{\A#{Regexp.escape(path.chomp('/'))}#{optional_slash ? '/?' : '(?:/|\z)'}}
  end

  def pwd
    @pwd ||= begin
      path, re = session[:pwd], path_re(repo_root)
      path =~ re && File.directory?(path) ? path : repo_root
    end
  end

  def relative_pwd
    @relative_pwd ||= pwd.sub(path_re(repo_root, true), '/')
  end

  def relative_path(*args)
    path_for_file(relative_pwd, *args)
  end

  def relative_url(*args)
    url_for(relative_path(*args))
  end

  def real_path(path)
    File.join(repo_root, path)
  end

  def chdir(path)
    @pwd = @relative_pwd = nil
    session[:pwd] = path
    get_files
    pwd
  end

  def get_files(dir = pwd)
    @files = Dir.entries(dir).sort - options.ignore
  end

  def extract_path
    @path = request.path_info
    @path, @action = $1, $2 if @path =~ %r{(.*)(?:;|%3B)(.*)}

    @real_path = real_path(@path)
    @base = File.basename(@path)

    @dir  = @base if File.directory?(@real_path)
    @file = @base if File.file?(@real_path)
  end

  def trail_links
    links, dirs = [], relative_pwd.split('/'); dirs.shift

    until dirs.empty?
      links.unshift(link_to(dirs.last, path_for_file(dirs)))
      dirs.pop
    end

    links.unshift(link_to('ROOT', '/'))
  end

  def real_params
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

  def repo_name
    @repo_name ||= File.basename(options.repo, '.git')
  end

  def repo_root
    @repo_root ||= File.join(options.tmpdir, "#{repo_name}-#{u(user)}")
  end

  def git
    @git ||= Git.open(repo_root, :log => options.logger)
  end

  def ensure_repo
    if File.directory?(File.join(repo_root, '.git'))
      pull if pull?
    else
      base, name = File.split(repo_root)

      git = Git.clone(options.repo, name, :path => base, :bare => false)
      git.config('user.name',  user)
      git.config('user.email', options.email % user)

      rake
    end
  end

  def pull?
    pulled, pulled_at = session[:pulled], session[:pulled_at]
    pulled != repo_root || !pulled_at || pulled_at < 12.hours.ago.utc
  end

  def pull
    stash = git.lib.stash_save('about to pull')

    git.pullpull

    session[:pulled]    = repo_root
    session[:pulled_at] = Time.now.utc

    begin
      git.lib.stash_apply
    rescue Git::GitExecuteError
      # conflict!!
    ensure
      git.lib.stash_clear
    end if stash

    !check_conflict(true)
  end

  def dirty?(path = nil)
    diff_total = if path
      git.diff.path(path).index_stats[:total]
    else
      @diff_total || git.diff.index_stats[:total]
    end

    !diff_total[:files].zero?
  end

  def conflicts(path = default = Object.new)
    if default
      @conflicts ||= conflicts(nil)
    else
      git.grep('<' * 7, path, :object => :nil, :name_only => true)
    end
  end

  def conflict?(path = nil)
    !conflicts(path).empty?
  end

  def check_conflict(oops = false)
    if conflict?
      flash :error => "#{oops ? 'Oops, now' : 'Sorry,'} you have conflicts!!"
      redirect url_for('/' + u(';status'))

      true
    else
      false
    end
  end

  def status_for(path)
    prefix = path.sub(/\A\//, '')
    re = %r{\A#{Regexp.escape(prefix)}(.*)}

    status, hash = git.status, { 'conflict' => conflicts(prefix) }

    %w[added changed deleted untracked].each { |type|
      hash[type] = status.send(type).map { |q, _| q[re, 1] }.compact
    }

    hash
  end

  def annotated_diff(path)
    git.diff.path(path).patch.split($/).map { |row|
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
  end

  def revert(path)
    git.reset(nil, :path_limiter => path, :quiet => true)
    git.checkout_index(:path_limiter => path, :index => true, :force => true)
  end

  def commit(msg)
    if pull
      git.commit_all(msg)
      git.push  # TODO: handle non-fast-forward?

      true
    end
  end

  def publish?
    git.fetch

    @tags = git.tags.reverse
    @logs = git.log(99)
    @logs.between(@tags.first) unless @tags.empty?

    @logs.any? || @tags.any?
  end

  def publish(tag)
    if tag == '_new'
      tag = "jc-#{Time.now.to_f}"
      git.add_tag(tag)
    else
      # delete tag so we can re-push it
      git.push('origin', ":#{tag}")
    end

    git.push('origin', tag)
  end

  def rake(*args)
    # TODO: error handling!
    Dir.chdir(repo_root) {
      system('rake', *args)
    }
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
      redirect url_for_file(@path)
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
    query_re = %r{#{query}}i

    match = case type.to_s
      when 'name'
        lambda { |path| File.basename(path) =~ query_re }
      when 'text'
        lambda { |path| File.file?(path) && File.read(path) =~ query_re }
      else
        flash :error => "Invalid type parameter `#{type}'."
    end or return

    matches, re, ignore = [], path_re(pwd), options.ignore

    Find.find(pwd) { |path|
      Find.prune if ignore.include?(File.basename(path))
      matches << path.sub(re, '') if match[path]
    }

    matches
  end

end; end
