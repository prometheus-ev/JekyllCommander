require 'git'

module Git

  class Base

    def diff_index_stats(treeish = 'HEAD', opts = {})
      lib.diff_index_stats(treeish, opts)
    end

    def reset_file(opts = {})
      lib.reset_file(opts.delete(:commit), opts)
    end

  end

  class Lib

    def diff_index_stats(treeish = 'HEAD', opts = {})
      diff_opts = ['--numstat']
      diff_opts << treeish
      diff_opts << '--' << opts[:path_limiter] if opts[:path_limiter].is_a? String

      hsh = {:total => {:insertions => 0, :deletions => 0, :lines => 0, :files => 0}, :files => {}}

      command_lines('diff-index', diff_opts).each do |file|
        (insertions, deletions, filename) = file.split("\t")
        hsh[:total][:insertions] += insertions.to_i
        hsh[:total][:deletions] += deletions.to_i
        hsh[:total][:lines] = (hsh[:total][:deletions] + hsh[:total][:insertions])
        hsh[:total][:files] += 1
        hsh[:files][filename] = {:insertions => insertions.to_i, :deletions => deletions.to_i}
      end

      hsh
    end

    def reset_file(commit, opts = {})
      arr_opts = []
      arr_opts << '--hard' if opts[:hard]
      arr_opts << '--quiet' if opts[:quiet]
      arr_opts << commit if commit
      arr_opts << '--' << opts[:path_limiter] if opts[:path_limiter].is_a? String
      command('reset', arr_opts)
    end

    def checkout_index(opts = {})
      arr_opts = []
      arr_opts << "--prefix=#{opts[:prefix]}" if opts[:prefix]
      arr_opts << "--index" if opts[:index]
      arr_opts << "--force" if opts[:force]
      arr_opts << "--all" if opts[:all]
      arr_opts << '--' << opts[:path_limiter] if opts[:path_limiter].is_a? String

      command('checkout-index', arr_opts)
    end

  end

  class Diff

    alias_method :_jc_original_initialize, :initialize

    def initialize(base, from = 'HEAD', to = nil)
      _jc_original_initialize(base, from, to)
      @to = to unless to
    end

  end

  class Log

    def empty?
      size.zero?
    end

  end

end
