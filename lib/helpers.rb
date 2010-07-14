require 'erb'
require 'active_support'

helpers do

  include ERB::Util

  def u2(path)
    path.split('/').map { |dir| u(dir) }.join('/')
  end

  def partial(page, options = {})
    erb page, options.merge(:layout => false)
  end

  def form(method = :post, url = relative_url)
    unless %w[get post].include?(method.to_s)
      method_override, method = method, :post
    end

    form = %Q{<form action="#{url}" method="post">}
    form << %Q{\n<input type="hidden" name="_method" value="#{method_override}" />} if method_override
    form
  end

  def form_new(type)
    form + %Q{\n<input type="hidden" name="type" value="#{type}" />}
  end

  def form_delete(type, url = relative_url)
    onclick = %q{onclick='if(!confirm("Are your sure?"))return false;'}
    form(:delete, url) + %Q{\n<p><button type="submit" #{onclick}>Delete #{type}</button></p>\n</form>}
  end

  def url_for(path)
    path.start_with?('/') ? "#{request.script_name}#{path}".gsub(%r{/+}, '/') : path
  end

  def url_for_file(*file)
    url_for("/#{u2(File.join(file))}")
  end

  def link_to(name, url, html_options = '')
    %Q{<a href="#{url_for(url)}"#{' ' + html_options unless html_options.empty?}>#{name}</a>}
  end

  def link_to_file(file, name = file)
    path, url = File.join(pwd, file), url_for_file(relative_pwd, file)

    if File.directory?(path)
      link_to("#{name}/", url)
    elsif File.file?(path)
      link_to(name, url)
    else
      "#{name}?"
    end
  end

  def language_links(page, current_lang)
    Page::LANGUAGES.map { |lang|
      if lang == current_lang
        lang.upcase
      else
        link_to_file(page.filename(lang), lang.upcase)
      end
    }.join(" |\n")
  end

  def link_to_preview(page)
    link_to('Preview', File.join(options.preview, relative_pwd, page.slug), 'target="_blank"')
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
    hash = {} unless hash.is_a?(Hash)
    hash[:title] ||= ''

    hash.map { |key, value|
      renderer = "render_#{key}_header"
      renderer = :render_header_field unless respond_to?(renderer)

      %Q{<p>
        <label for="page_#{key}">#{key.to_s.humanize}</label>:<br />
        #{send(renderer, key, value)}
      </p>}
    }.join
  end

  def render_header_field(key, value)
    %Q{<input type="text" name="header[#{key}]" id="page_#{key}" value="#{value}" size="50" />}
  end

  def render_layout_header(key = :layout, value = 'default')
    select = %Q{<select name="#{key}" id="page_#{key}">}

    layouts = Dir[File.join(options.jekyll_root, '_layouts', '*.html')]
    layouts.map! { |layout| File.basename(layout, '.html') }
    layouts.sort!

    layouts.each { |layout|
      select << %Q{\n<option#{ ' selected="selected"' if layout == value }>#{layout}</option>}
    }

    select << "\n</select>"
  end

  def pwd
    @pwd ||= begin
      path, root = session[:pwd], options.jekyll_root
      path =~ %r{\A#{Regexp.escape(root)}(?:/|\z)} && File.directory?(path) ? path : root
    end
  end

  def relative_pwd
    @relative_pwd ||= pwd.sub(%r{\A#{Regexp.escape(options.jekyll_root)}/?}, '/')
  end

  def relative_url(*args)
    url_for_file(relative_pwd, *args)
  end

  def real_path(path)
    File.join(options.jekyll_root, path)
  end

  def chdir(path)
    @pwd = @relative_pwd = nil
    session[:pwd] = path
    pwd
  end

  def get_files(dir = pwd)
    @files = Dir.entries(dir).sort - IGNORE
  end

  def trail
    trail, dirs = [], relative_pwd.split('/'); dirs.shift

    until dirs.empty?
      trail.unshift(link_to(dirs.last, url_for_file(dirs)))
      dirs.pop
    end

    trail.unshift(link_to('ROOT', '/')).join(' / ')
  end

  def extract_language
    @lang = Page.lang(@path)
  end

  #def git_status
  #  Dir.chdir(pwd) { $git.git.status }
  #end

end
