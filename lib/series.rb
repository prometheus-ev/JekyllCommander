module JekyllCommander

  class Series < Page

    IMAGES = Array.new(8) { |i| "0#{i + 1}.jpg" } + ['start.jpg']

    DEFAULT_OPTIONS = [[:multilang, true], [:render, true]]

    DATE_RE   = %r{\A(\d{4})\W(\d{2})\W(\d{2})\z}
    NUMBER_RE = %r{\A(\d{2})\W(\d{4})\z}

    attr_accessor :date, :author, :subtitle, :teaser

    attr_reader :number

    def initialize(root, base, title = nil, options = {})
      super(root, base, title, DEFAULT_OPTIONS + options)

      @number = base.split(%r{(/)})[-3..-1].reverse.join
      @number = nil unless @number =~ NUMBER_RE
    end

    def slug
      'index'
    end

    def set_default_header
      default_header = {
        :title        => title,
        :subtitle     => subtitle,
        :teaser       => teaser,
        :layout       => 'series',
        :descriptions => [],
        :author       => author,
        :date         => date
      }

      translated { |lang|
        send("header_#{lang}=", default_header) unless header(lang)
      }
    end

    def author=(value)
      translated { |lang| header(lang)[:author] = value }
    end

    def date=(value)
      @date = value =~ DATE_RE ? Regexp.last_match.captures.join('/') :
                                 Time.now.strftime("%Y/%m/%d")

      translated { |lang| header(lang)[:date] = @date }
    end

  end

end
