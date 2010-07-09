require "erb"
require "active_support"
include ERB::Util

helpers do
  def partial(page, options={})
    erb page, options.merge!(:layout => false)
  end

  def link_to(name, url, html_options = '')
    "<a href=\"#{url}\"#{' ' + html_options unless html_options.empty?}>#{name}</a>"
  end

  def link_to_file(file)
    path = File.join($pwd, file)
    file = '__up' if file == '..'
    if File.directory?(path)
      "d #{link_to(file, "/chdir/#{u(file)}")}"
    elsif File.file?(path)
      "f #{link_to(file, "/edit/#{u(file)}")}"
    else
      'x'
    end
  end

  def language_links(page, current_lang)
    Page.languages.collect { |lang|
      if lang == current_lang
        lang.upcase
      else
        link_to(lang.upcase, options.self_url + '/edit/' + page.filename(lang))
      end
    }.join(" |\n")
  end

  def header_fields(hash)
    hash = Hash.new unless hash.is_a?(Hash)
    hash = hash.stringify_keys
    hash['title'] ||= ''
    out = ''

    hash.each { |k, v|
      out << %{<p>
        #{k.humanize}:<br />
        <input type="text" size="50" name="header[#{k}]" value="#{v}">
      </p>}
    }
    return out
  end

  def link_to_preview(page)
    link_to('Preview', File.join(options.preview, relative_pwd, page.slug), 'target="_blank"')
  end

  def flash
    session.delete(:flash)
  end

  def files_of(dir = $pwd)
    @files = Dir.entries(dir).collect { |file|
      file unless INVISIBLE.include?(file)
    }.compact.sort
  end

  def chdir(path)
    if File.directory?(path) && File.directory?(path)
      $pwd = session[:pwd] = path
    else
      $pwd = session[:pwd] = options.jekyll_root
    end
  end

  def relative_pwd
    @relative_pwd ||= $pwd.gsub(options.jekyll_root, '') + '/'
  end

  def lang_from_filename(filename)
    @lang_from_filename ||= filename.split('.')[-2]
    return @lang_from_filename if Page.languages.include?(@lang_from_filename)
  end

  #def git_status
  #  Dir.chdir($pwd) { $git.git.status }
  #end
end
