module JekyllCommander

  class Post < Page

    attr_accessor :date, :author

    def slug
      return @slug if @slug

      title = @title && @title.
        replace_diacritics.downcase.
        gsub(/\W+/, '-').gsub(/\A-|-\z/, '')

      @slug = "#{date}-#{title}"
    end

    def set_default_header
      default_header = {
        :title  => title,
        :layout => 'post',
        :tags   => [],
        :author => author
      }

      translated { |lang|
        send("header_#{lang}=", default_header) unless header(lang)
      }
    end

    def author=(value)
      translated { |lang| header(lang)[:author] = value } if render?
    end

    def date=(value)
      if value =~ /(\d{4})\W(\d{2})\W(\d{2})/
        @date = "#{$1}-#{$2}-#{$3}"
      else
        @date = Time.now.strftime("%Y-%m-%d")
      end
    end

  end

end
