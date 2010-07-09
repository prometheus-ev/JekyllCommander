class Page
  LANGUAGES = %w{en de}
  MARKUPS   = %w{textile markdown html}

  attr :markup, :slug
  LANGUAGES.each {|lang| attr "header_#{lang}".to_sym, "body_#{lang}".to_sym }

  def initialize(title, options = {})
    @markup    = options[:markup].nil? || !MARKUPS.include?(options[:markup]) ? 'textile' : options[:markup]
    @multilang = options[:multilang].nil? ? true : options[:multilang]
    @render    = options[:render].nil?    ? true : options[:render]
    @title     = title

    if render?
      langs = multilang? ? LANGUAGES : [LANGUAGES.first]
      LANGUAGES.each do |l|
        instance_variable_set("@header_#{l}".to_sym, {
          :title  => @title,
          :layout => 'default'
        })
      end
    end

    @errors = []
  end

  def title(lang = LANGUAGES.first)
    return @title if lang == LANGUAGES.first && @title

    var_name = "@header_#{lang}"
    if instance_variable_defined?(var_name.to_sym)
      header = instance_variable_get(var_name)
      if header && header[:title]
        @title = header[:title] if lang == LANGUAGES.first
        header[:title]
      else
        slug
      end
    else
      slug
    end
  end

  def header(lang = LANGUAGES.first)
    var_name = "@header_#{lang}"
    instance_variable_get(var_name) if instance_variable_defined?(var_name.to_sym)
  end

  def body(lang = LANGUAGES.first)
    var_name = "@body_#{lang}"
    instance_variable_get(var_name) if instance_variable_defined?(var_name.to_sym)
  end

  def slug
    @slug ||= @title.replace_diacritics.
      gsub(/(?:[^a-zA-Z0-9]|_)+/, '_').
      gsub(/\A_+|_+\z/, '')
  end

  def multilang?
    @multilang
  end

  def render?
    @render
  end

  def update(attributes = {}, lang = LANGUAGES.first)
    attributes.each { |k, v|
      if k == 'slug'
        @slug = v
      else
        instance_variable_set("@#{k.to_s}_#{lang}".to_sym, v)
      end
    }
    self if valid?
  end

  def destroy
    success = true

    filenames.each do |f|
      unless File.delete(File.join($pwd, f))
        @errors << "Unable to delete file '#{f}'."
        success = false
      end
    end

    return success
  end

  def self.page_file?(path)
    File.basename(path) =~ /.+\.\w{2}\.\w+/
  end

  def self.languages
    LANGUAGES
  end

  def self.load(path)
    if File.exist?(path)
      ext = path.split('.').last
      page = self.new(nil)

      page.instance_variable_set(:@markup, ext) if MARKUPS.include?(ext)

      if Page.page_file?(path)
        multilang = true
        base_path = path.gsub(/\.\w{2}\.\w+$/, '')
        LANGUAGES.each { |lang|
          file = "#{base_path}.#{lang}.#{ext}"
          Page.load_file(file, page, lang)
        }
      else
        multilang = false
        base_path = path.gsub(/\.\w+$/, '')
        Page.load_file(path, page)
      end
      page.instance_variable_set(:@slug, File.basename(base_path))
      page.instance_variable_set(:@multilang, multilang)

      title = page.title ? page.title : page.slug
      page.instance_variable_set(:@title, title)

      return page
    else
      return false
    end
  end

  def self.load_file(file, page, lang = LANGUAGES.first)
    if File.exist?(file)
      content = File.open(file, 'r') { |f| f.read } if File.exist?(file)
      if matched = content.match(/^(---\s*\n.*?\n?)^---\s*$\n?(.*)/m)
        page.instance_variable_set("@header_#{lang}".to_sym, YAML.load(matched[1])) if matched.size == 3
        body = matched[2]
      else
        body = content
        page.instance_variable_set(:@render, false)
      end
      page.instance_variable_set("@body_#{lang}".to_sym, body)
    end
  end

  def write!
    if valid?
      if multilang?
        LANGUAGES.each do |l|
          write_file(File.join($pwd, filename(l)), to_s(l))
        end
      else
        write_file(File.join($pwd, filename), to_s)
      end
      return true
    else
      return false
    end
  end

  def write_file(path, content)
    # git_add = !File.exist?(path)
    File.open(path, 'w') { |f| f.print(content) }
    if git_add
      # Dir.chdir($pwd) { $git.add(File.basename(path)) }
      # git_commit_msg = "Added file for '#{title}'"
    else
      # git_commit_msg = "Edited file for '#{title}'"
    end
    # Dir.chdir($pwd) { $git.index.commit(git_commit_msg, [$git.commits.first], $git_actor, $git.tree) }
  end

  def write
    unless exist?($pwd)
      write!
    else
      @errors << 'File already exists.'
      return false
    end
  end

  def to_s(lang = LANGUAGES.first)
    out = ''
    if header(lang)
      out << header(lang).to_yaml + "---\n"
    end
    out << body(lang) if body(lang)

    return out
  end

  def filename(lang = LANGUAGES.first)
    if multilang?
      "#{slug}.#{lang}.#{@markup}"
    else
      "#{slug}.#{@markup}"
    end
  end

  def filenames
    if multilang?
      LANGUAGES.collect { |l| filename(l) }
    else
      [filename]
    end
  end

  def valid?
    valid = true

    if !title.is_a?(String) || title.empty?
      @errors << 'Invalid title.'
      valid = false
    end

    if !MARKUPS.include?(@markup)
      @errors << 'Invalid format.'
      valid = false
    end

    return valid
  end

  def exist?(path)
    filenames.collect { |fn|
      File.join(path, fn)
    }.collect { |fp|
      File.exist?(fp)
    }.include?(true)
  end

  def errors
    @errors.uniq
  end

end
