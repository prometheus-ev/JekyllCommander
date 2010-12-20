module JekyllCommander

  class Series < Page

    IMAGES = Array.new(8) { |i| "0#{i + 1}.jpg" } + ['start.jpg']

    attr_accessor :date, :author

    def initialize(root, base, title = nil, options = {})
      options = [[:multilang, true], [:render, true]] + options
      super(root, base, title, options)
    end

    def slug
      'index'
    end

    def set_default_header
      default_header = {
        :title        => title,
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
      if value =~ /(\d{4})\W(\d{2})\W(\d{2})/
        @date = "#{$1}/#{$2}/#{$3}"
      else
        @date = Time.now.strftime("%Y/%m/%d")
      end
      translated { |lang| header(lang)[:date] = @date }
    end

  end

end
