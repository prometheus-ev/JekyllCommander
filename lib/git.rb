require 'grit'

module JekyllCommander

  class Git

    GIT_DIR = '.git'

    CONFLICT_MARKER = '<' * 7

    STATUS_TYPE_MAP = {
      'A' => 'added',
      'M' => 'changed',
      'D' => 'deleted'
    }

    STATUS_KEYS = %w[
      conflict
      untracked
    ].concat(STATUS_TYPE_MAP.values)

    UNTRACKED_RE = %r{\A\?\?\s+}

    NUMSTAT_RE   = %r{^([-\d]+)\s+([-\d]+)\s+(.+)}

    def self.setup(logger = nil, timeout = nil)
      Grit.debug = if logger
        Grit.logger = logger unless logger == true
        true
      else
        false
      end

      Grit::Git.git_timeout = timeout
    end

    attr_reader :repo_root, :git_dir, :error_handler, :err

    def initialize(repo_root, *args, &block)
      @repo_root = File.expand_path(repo_root)
      @git_dir   = File.join(@repo_root, GIT_DIR)

      @error_handler = block

      self.class.setup(*args)
    end

    def repo
      @repo ||= Grit::Repo.new(repo_root)
    rescue Grit::InvalidGitRepositoryError, Grit::NoSuchPathError
      raise RepositoryError.new(repo_root)
    end

    def git
      @git ||= repo.git
    end

    def exist?
      File.directory?(git_dir)
    end

    def in_repo(chdir = true)
      chdir != false ? Dir.chdir(repo_root) { yield } : yield
    end

    def handle_error(err)
      @err = err
      error_handler ? error_handler[err] : raise(err)
    end

    def handle_success(res)
      @err = nil
      block_given? ? yield(res) : res
    end

    def failed?
      !!err
    end

    include module GitCommands

      def add(path)
        git_cmd(:add, [], :path => path)
      end

      def checkout(*args)
        git_cmd(:checkout, args)
      end

      def checkout_index(path = nil, *args)
        git_cmd(:checkout_index, args, :path => path)
      end

      def checkout_path(path = nil, *args)
        git_cmd(:checkout, args, :path => path)
      end

      def clone(repo_url, *args, &block)
        init_cmd(:clone, [repo_url, *args], &block)
      end

      def commit_all(msg, *args)
        git_cmd(:commit, args, :message => msg, :all => true)
      end

      def config
        @config ||= repo_cmd(:config)
      end

      def conflicts(path = nil)
        grep(CONFLICT_MARKER, :path => path, :name_only => true)
      end

      def delete_tag(tag, remote = 'origin')
        push(remote, ":#{tag}")
      end

      def diff(*args)
        diff_cmd(:diff!, *args)
      end

      def diff_index(*args)
        diff_cmd(:diff_index, *args)
      end

      def diff_stats(path = nil, tree = 'HEAD', *args)
        options = { :numstat => true }
        args.last.is_a?(Hash) ? args.last.update(options) : args << options

        total, stats = Hash.new(0), {}

        res = diff_index(path, tree, *args)
        res.each { |line|
          next unless line =~ NUMSTAT_RE
          add, del, file = $1, $2, $3

          total[:files] += 1

          total[:additions] += add = add.to_i
          total[:deletions] += del = del.to_i

          stats[file] = { :additions => add, :deletions => del }
        } unless failed?

        [total, stats]
      end

      def fetch(remote = 'origin', branch = nil, *args)
        git_cmd(:fetch, [remote, branch, *args])
      end

      def grep(pattern, *args)
        git_lines(:grep, args, :e => pattern, :raise => false)
      end

      def init(*args, &block)
        init_cmd(:init, args, &block)
      end

      def log(*args)
        repo_cmd(:log, args)
      end

      def mv(src, dst)
        git_cmd(:mv, [], :path => [src, dst])
      end

      def pull(remote = 'origin', branch = 'master', *args)
        git_cmd(:pull, [remote, branch, *args])
      end

      def push(remote = 'origin', branch = 'master', *args)
        git_cmd(:push, [remote, branch, *args])
      end

      def push_tag(tag, remote = 'origin', *args)
        push(remote, tag, *args)
      end

      def reset(path = nil, *args)
        git_cmd(:reset, args, :path => path)
      end

      def revert(path = nil)
        reset(path, :quiet => true)
        checkout_path(path, :force => true)
      end

      def rm(path, *args)
        translate_options!(args.last, :recursive => :r)
        git_cmd(:rm, args, :path => path, :force => true)
      end

      def stash(cmd, *args)
        opts = args.last.is_a?(Hash) ? git.options_to_argv(args.pop) : []
        git_cmd(:stash, [cmd, *opts.concat(args)]) { |res|
          res !~ /\ANo local changes to save/
        }
      end

      def status(*args)
        git_lines(:status, args)
      end

      def status_for(path)
        path = path.sub(/\A\//, '')
        re   = %r{\A#{Regexp.escape(path)}(.*)}
        trim = lambda { |file_path| file_path[re, 1] }

        hash = STATUS_KEYS.inject({}) { |h, k| h[k] = []; h }

        res = conflicts(path)
        hash['conflict']  = res.map! { |f| trim[f] } unless failed?

        res = untracked(path)
        hash['untracked'] = res.map! { |f| trim[f] } unless failed?

        repo_cmd(:status).each { |status_file|
          if key = STATUS_TYPE_MAP[status_file.type]
            file_path = trim[status_file.path]
            hash[key] << file_path if file_path
          end
        }

        hash
      end

      def tag(tag, *args)
        git_cmd(:tag, [tag, *args])
      end

      def tags
        repo_cmd(:tags).sort_by { |tag| tag.commit.authored_date }.reverse
      end

      def untracked(path = nil)
        res = status(:path => path, :short => true, :untracked => 'all')
        failed? ? res : res.map { |line| line.sub!(UNTRACKED_RE, '') }.compact
      end

      private

      def repo_cmd(cmd, args = [], options = {}, &block)
        run_cmd(repo, cmd, args, options, &block)
      end

      def init_cmd(cmd, args = [], options = {})
        git_cmd(cmd, args, {
          :git   => Grit::Git.new(git_dir),
          :path  => repo_root,
          :chdir => false,
          :base  => false
        }.merge(options)) { |res|
          yield config if block_given?
        }

        self unless failed?
      end

      def diff_cmd(cmd, path = nil, tree = 'HEAD', *args)
        git_lines(cmd, [tree, *args], :path => path)
      end

      def git_cmd(cmd, args = [], options = {}, &block)
        options.update(args.pop) if args.last.is_a?(Hash)
        args.unshift(options)

        options[:raise] = true unless options.has_key?(:raise)

        path = options.delete(:path)
        args.push('--').concat(Array(path)) if path

        if native_cmd = cmd.to_s.sub!(/!\z/, '')
          args.unshift(native_cmd)
          cmd = :native
        end

        run_cmd(options.delete(:git) || git, cmd, args, options, &block)
      end

      def git_lines(*args)
        git_cmd(*args) { |res| res.split($/) }
      end

      def run_cmd(target, cmd, args = [], options = {}, &block)
        res = in_repo(options.delete(:chdir)) { target.send(cmd, *args) }
      rescue Grit::Git::CommandFailed => err
        handle_error(CommandError.new(err.command, err.err))
      else
        handle_success(res, &block)
      end

      def translate_options!(hash, translations)
        translations.each { |from, to|
          hash[to] = hash.delete(from) if hash.has_key?(from) && !hash.has_key?(to)
        } if hash.is_a?(Hash)
      end

      self  # must be the last statement! ;-)

    end

    class GitError < StandardError
    end

    class RepositoryError < GitError

      attr_reader :path

      def initialize(path)
        @path = path
        super "Invalid Git repository: #{path}"
      end

    end

    class CommandError < GitError

      attr_reader :cmd, :err

      def initialize(cmd, err)
        @cmd, @err = cmd, err
        super "Git command failed: #{cmd}"
      end

    end

  end

end
