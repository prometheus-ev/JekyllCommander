require 'erb'
require 'git'
require 'active_support'

module JekyllCommander; module Helpers

  include ERB::Util

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
    form(:delete, url) + %Q{\n<p><button type="submit" #{onclick}>#{text}</button></p>\n</form>}
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
    attributes = [%Q{href="#{url_for(url)}"}]

    case html_options
      when String
        attributes << html_options
      when Array
        attributes.concat(html_options)
      when Hash
        attributes.concat(html_options.map { |k, v| %Q{#{k}="#{v}"} })
    end unless html_options.empty?

    "<a #{attributes.join(' ')}>#{name}</a>"
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
        lang.upcase
      else
        link_to_file(page.filename(lang), lang.upcase)
      end
    }.join(" |\n")
  end

  def link_to_preview
    link_to('Preview', relative_path("#{@file};preview"), :target => '_blank')
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
    hash.map { |key, value|
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

  def pwd
    @pwd ||= begin
      path, re = session[:pwd], %r{\A#{Regexp.escape(repo_root)}(?:/|\z)}
      path =~ re && File.directory?(path) ? path : repo_root
    end
  end

  def relative_pwd
    @relative_pwd ||= pwd.sub(%r{\A#{Regexp.escape(repo_root)}/?}, '/')
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

  def trail
    trail, dirs = [], relative_pwd.split('/'); dirs.shift

    until dirs.empty?
      trail.unshift(link_to(dirs.last, path_for_file(dirs)))
      dirs.pop
    end

    trail.unshift(link_to('ROOT', '/')).join(' / ')
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
      return
    end

    base, name = File.split(repo_root)

    git = Git.clone(options.repo, name, :path => base, :bare => false)
    git.config('user.name',  user)
    git.config('user.email', options.email % user)
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

    !check_conflict
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

  def check_conflict
    if conflict?
      flash :error => 'You have conflicts!!'
      redirect url_for('/' + u(';status'))

      true
    else
      false
    end
  end

end; end
