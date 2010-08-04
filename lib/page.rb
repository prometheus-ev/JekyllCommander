require 'git'
require 'active_support'
require 'nuggets/util/i18n'
require 'jekyll/convertible'

module JekyllCommander; class Page

  PageFile = Struct.new(:content, :data) {
    include Jekyll::Convertible

    def self.read_yaml(base, name)
      page_file = new
      page_file.read_yaml(base, name)
      [page_file.content, page_file.data]
    end
  }

  TYPE = Hash.new(:page).merge(
    '_includes'   => :include,
    '_layouts'    => :layout,
    '_posts'      => :post,
    'files'       => :file,
    'javascripts' => :javascript,
    'stylesheets' => :stylesheet
  )

  LANGUAGES = %w[en de]
  DEFAULT_LANGUAGE = LANGUAGES.first

  TRANSLATES_ATTRS = %w[header body]
  TRANSLATED_ATTRS = TRANSLATES_ATTRS.map { |attr|
    LANGUAGES.map { |lang| "#{attr}_#{lang}" }
  }.flatten

  MARKUPS    = %w[textile markdown html]
  NO_MARKUPS = %w[yml xml js css]

  NO_MARKUP = 'none'; MARKUPS << NO_MARKUP
  DEFAULT_MARKUP = MARKUPS.first

  MARKUP_LINKS = {
    :textile => [
      %w[Syntax http://redcloth.org/hobix.com/textile/],
      %w[Demo   http://textile.thresholdstate.com/]
    ],
    :markdown => [
      %w[Syntax http://daringfireball.net/projects/markdown/syntax],
      %w[Demo   http://daringfireball.net/projects/markdown/dingus]
    ],
    :html => [
      %w[Syntax http://de.selfhtml.org/]
    ]
  }

  EXT_RE = %r{(?:\.(#{LANGUAGES.join('|')}))?(?:\.(\w+))?\z}

  class << self

  def type(path)
    TYPE[path.sub(%r{\A/}, '').sub(%r{/.*}, '')]
  end

  def lang(path)
    path =~ EXT_RE
    LANGUAGES.include?($1) ? $1 : DEFAULT_LANGUAGE
  end

  def load(root, path)
    return unless File.file?(File.join(root, path))

    base, name = File.split(path)

    new(root, base, nil, [
      [:lang,      lang(name)],
      [:slug,      name.sub(EXT_RE, '')],
      [:ext,       $2],
      [:markup,    $2],
      [:multilang, $1]
    ]).load
  end

  end

  attr_accessor :root, :base, :title, :slug, :ext, :markup,
                :render, :lang, :multilang, *TRANSLATED_ATTRS

  def initialize(root, base, title = nil, options = {})
    @root, @base, @title, @errors = root, base.sub(%r{\A/}, ''), title, []

    # this one is essential, so we set it first
    @lang = Array(options.to_a.assoc(:lang)).last || DEFAULT_LANGUAGE

    options.each { |key, value| send("#{key}=", value) }
  end

  def load
    translated { |lang|
      next unless exist?(lang)

      if markup?
        body, header = PageFile.read_yaml(basepath, filename(lang))

        if header.empty?
          header = nil
          self.render = false
        else
          self.render = true
        end
      else
        self.render = false

        if ext == 'yml'
          header = YAML.load_file(fullpath(lang))
        elsif ext == 'xml'
          body, header = PageFile.read_yaml(basepath, filename(lang))
        else
          body = File.read(fullpath(lang))
        end
      end

      send("header_#{lang}=", header.symbolize_keys) if header
      send("body_#{lang}=", body)
    }

    self
  end

  alias_method :multilang?, :multilang
  alias_method :render?, :render
  alias_method :ext?, :ext

  def ext=(value)
    @ext = NO_MARKUPS.include?(value) ? value : nil
  end

  def markup?
    markup != NO_MARKUP
  end

  def markup=(value)
    @markup = value.blank? || ext?    ? NO_MARKUP :
              MARKUPS.include?(value) ? value     :
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
    attributes.each { |key, value|
      value.symbolize_keys! if value.is_a?(Hash)

      if TRANSLATES_ATTRS.include?(key.to_s)
        original = send("#{key}_#{lang}")

        case [original.class, value.class]
          when [Hash, Hash]
            value.each_key { |k|
              if [original[k].class, value[k].class] == [Array, String]
                value[k] = value[k].split("\r\n")
              end
            }
          when [Array, String]
            value = value.split("\r\n")
        end

        send("#{key}_#{lang}=", value)
      elsif respond_to?(setter = "#{key}=")
        send(setter, value)
      else
        @errors << "Illegal attribute `#{key}'."
      end
    }

    self if valid?
  end

  def destroy(git = nil)
    translated(:fullpath).reject { |path|
      git.remove(path) rescue nil if git
      File.exist?(path) ? File.delete(path) : true
    }.each { |path|
      @errors << "Unable to delete file `#{path}'."
    }.empty?
  end

  def write(git = nil)
    unless exist?
      write!(git)
    else
      @errors << "Page `#{fullpath}' already exists."
      false
    end
  end

  def write!(git = nil)
    translated { |lang|
      path = fullpath(lang)
      File.open(path, 'w') { |f| f.puts to_s(lang) }
      git.add(path) if git
    } if valid?
  end

  def to_s(lang = lang)
    out = ''

    body, header = body(lang), header(lang)
    separator = "---\n" if header && (body || render?)

    out << header.stringify_keys.to_yaml if header
    out << separator                     if separator
    out << body.gsub(/\r\n/, "\n")       if body

    out
  end

  def filename(lang = lang)
    name  = "#{slug}"
    name << ".#{lang}"   if multilang?
    name << ".#{markup}" if markup?
    name << ".#{ext}"    if ext?
    name
  end

  def basepath
    @basepath ||= File.join(root, base)
  end

  def fullpath(lang = lang)
    File.join(basepath, filename(lang))
  end

  def valid?
    if title.blank?
      @errors << "Required attribute `title' is missing!"
    elsif slug.blank?
      @errors << "Required attribute `slug' is missing!"
    end

    unless MARKUPS.include?(markup)
      @errors << "Invalid format `#{markup}'."
    end

    @errors.empty?
  end

  def exist?(lang = nil)
    if lang
      File.exist?(fullpath(lang))
    else
      translated { |lang| return true if File.exist?(fullpath(lang)) }
      File.exist?(File.join(basepath, slug)) unless slug.blank?
    end
  end

  def errors
    @errors.uniq!
    @errors
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

  def type
    @type ||= self.class.type(base)
  end

end; end
