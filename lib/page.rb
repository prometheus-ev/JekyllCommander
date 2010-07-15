require 'active_support'
require 'nuggets/util/i18n'
require 'jekyll/convertible'

class Page

  PageFile = Struct.new(:content, :data) {
    include Jekyll::Convertible

    def self.read_yaml(base, name)
      page_file = new
      page_file.read_yaml(base, name)
      [page_file.content, page_file.data]
    end
  }

  LANGUAGES = %w[en de]
  DEFAULT_LANGUAGE = LANGUAGES.first

  TRANSLATES_ATTRS = %w[header body]
  TRANSLATED_ATTRS = TRANSLATES_ATTRS.map { |attr|
    LANGUAGES.map { |lang| "#{attr}_#{lang}" }
  }.flatten

  MARKUPS   = %w[textile markdown html]
  NO_MARKUP = 'none'; MARKUPS << NO_MARKUP
  DEFAULT_MARKUP = MARKUPS.first

  EXT_RE = %r{\.([a-z]{2})(?:\.(\w+))?\z}

  def self.lang(path)
    path =~ EXT_RE
    LANGUAGES.include?($1) ? $1 : DEFAULT_LANGUAGE
  end

  def self.load(path)
    return unless File.file?(path)

    base, name = File.split(path)

    new(base, nil, [
      [:lang,      lang(name)],
      [:slug,      name.sub(EXT_RE, '')],
      [:markup,    $2],
      [:multilang, $1]
    ]).load
  end

  attr_accessor :root, :title, :slug, :markup, :render,
                :lang, :multilang, *TRANSLATED_ATTRS

  def initialize(root, title = nil, options = {})
    @root, @title, @errors = root, title, []

    # this one is essential, so we set it first
    @lang = Array(options.to_a.assoc(:lang)).last || DEFAULT_LANGUAGE

    options.each { |key, value| send("#{key}=", value) }
  end

  def load
    translated { |lang|
      body, header = PageFile.read_yaml(root, filename(lang))

      if header.empty?
        self.render = false
      else
        self.render = true
        send("header_#{lang}=", header.symbolize_keys)
      end

      send("body_#{lang}=", body)
    }

    self
  end

  alias_method :multilang?, :multilang
  alias_method :render?, :render

  def markup?
    markup != NO_MARKUP
  end

  def markup=(value)
    @markup = value.nil? || value.empty? ? NO_MARKUP      :
              MARKUPS.include?(value)    ? value          :
                                           DEFAULT_MARKUP
  end

  def render=(value)
    value ? set_default_header : unset_header
    @render = value
  end

  def layout=(value)
    translated { |lang| header(lang)[:layout] = value } if render?
  end

  def slug
    @slug ||= @title && @title.replace_diacritics.
      gsub(/[^a-zA-Z0-9]+/, '_').
      gsub(/\A_+|_+\z/, '')
  end

  def title(lang = lang)
    default_lang = lang == DEFAULT_LANGUAGE
    return @title if @title && default_lang

    if header = header(lang) and title = header[:title]
      @title = title if default_lang
    end

    title || slug
  end

  def header(lang = lang)
    send("header_#{lang}")
  end

  LANGUAGES.each { |lang|
    class_eval <<-EOT, __FILE__, __LINE__ + 1
      def header_#{lang}=(value)
        if value.is_a?(Hash)
          (@header_#{lang} ||= {}).update(value.symbolize_keys)
        else
          @header_#{lang} = value
        end
      end
    EOT
  }

  def body(lang = lang)
    send("body_#{lang}")
  end

  def update(attributes = {}, lang = lang)
    p attributes
    attributes.each { |key, value|
      if TRANSLATES_ATTRS.include?(key.to_s)
        send("#{key}_#{lang}=", value)
      elsif respond_to?(setter = "#{key}=")
        send(setter, value)
      else
        @errors << "Illegal attribute `#{key}'."
      end
    }

    self if valid?
  end

  def destroy
    translated(:fullpath).reject { |path|
      File.delete(path)
    }.each { |path|
      @errors << "Unable to delete file `#{path}'."
    }.empty?
  end

  def write
    unless exist?
      write!
    else
      @errors << 'Already exists.'
      false
    end
  end

  def write!
    translated { |lang| write_file(lang) } if valid?
  end

  def write_file(lang = lang)
    path = fullpath(lang)

    #git_add = !File.exist?(path)

    File.open(path, 'w') { |f| f.puts to_s(lang) }

    #if git_add
    #  Dir.chdir(root) { $git.add(File.basename(path)) }
    #  msg = "Added file for `#{title}'."
    #else
    #  msg = "Edited file for `#{title}'."
    #end

    #Dir.chdir(root) { $git.index.commit(msg, [$git.commits.first], $git_actor, $git.tree) }
  end

  def to_s(lang = lang)
    out = ''

    body, header = body(lang), header(lang)

    out << header.stringify_keys.to_yaml + "---\n" if header
    out << body.gsub(/\r\n/, "\n") if body

    out
  end

  def filename(lang = lang)
    name  = "#{slug}"
    name << ".#{lang}"   if multilang?
    name << ".#{markup}" if markup?
    name
  end

  def fullpath(lang = lang)
    File.join(root, filename(lang))
  end

  def valid?
    @errors << 'Invalid slug.'   unless slug.is_a?(String) && !slug.empty?
    @errors << 'Invalid title.'  unless title.is_a?(String) && !title.empty?
    @errors << 'Invalid format.' unless MARKUPS.include?(@markup)

    @errors.empty?
  end

  def exist?
    translated { |lang| return true if File.exist?(fullpath(lang)) }
    false
  end

  def errors
    @errors.uniq
  end

  def set_default_header
    default_header = { :title => title, :layout => 'default' }

    translated { |lang|
      send("header_#{lang}=", default_header) unless header(lang)
    }
  end

  def unset_header
    LANGUAGES.each { |lang| send("header_#{lang}=", nil) }
  end

  def translated(method = nil)
    languages = multilang? ? LANGUAGES : [DEFAULT_LANGUAGE]

    if method
      languages.map { |lang| send(method, lang) }
    else
      languages.each { |lang| yield lang }
    end
  end

end
