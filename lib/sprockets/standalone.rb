require "sprockets/standalone/version"
require "rake"
require "rake/tasklib"
require "sprockets"

module Sprockets
  module Standalone
    class RakeTask < ::Rake::TaskLib
      # List of sprocket file targets that
      # should be compiled.
      attr_accessor :assets

      # List of source directories. This is a convenience
      # method as it will add all available sub-directories
      # like `stylesheets`, `javascripts` to sprockets
      # include path.
      #
      # Example: If you have a typical sprockets directory
      # layout like `src/assets/stylesheets`,
      # `src/assets/javascripts` all you need to add to
      # `source` is `src/assets`.
      attr_accessor :sources

      # Set output directory. Defaults to `dist` in current
      # working directory.
      attr_accessor :output

      # If assets should include digest. Default is false.
      attr_accessor :digest

      # If assets should be compressed. Default is false.
      attr_accessor :compress

      # `Environment` instance used for finding assets.
      attr_accessor :environment

      def index
        @index ||= environment.index if environment
      end

      def manifest
        @manifest ||= Sprockets::Standalone::Manifest.new index, File.join(output, "manifest.json")
      end

      def initialize(*args)
        @namespace   = args.shift || :assets
        @assets      = %w(application.js application.css *.png *.jpg *.gif)
        @sources     = []
        @output      = File.expand_path('dist', Dir.pwd)
        @digest      = false
        @compress    = false

        @environment = Sprockets::Environment.new(Dir.pwd) do |env|
          env.logger = Logger.new $stdout
          env.logger.level = Logger::INFO
        end

        yield self, environment if block_given?

        Array(sources).each { |source| environment.append_path source }

        manifest.compress_assets = !!@compress
        manifest.digest_assets   = !!@digest

        namespace @namespace do
          desc 'Compile assets'
          task :compile do
            manifest.compile *Array(assets)
          end

          desc 'Remove all assets'
          task :clobber do
            manifest.clobber
          end

          desc 'Clean old assets'
          task :clean do
            manifest.clean
          end
        end
      end
    end

    class Manifest < ::Sprockets::Manifest
      attr_writer :digest_assets
      def digest_assets?
        !!@digest_assets
      end

      attr_writer :compress_assets
      def compress_assets?
        !!@compress_assets
      end

      def compile(*args)
        unless environment
          raise Error, "manifest requires environment for compilation"
        end

        filenames = []

        find(*args) do |asset|
          # PATCH: override path
          path = digest_assets? ? asset.digest_path : asset.logical_path

          files[path] = {
            'logical_path' => asset.logical_path,
            'mtime'        => asset.mtime.iso8601,
            'size'         => asset.bytesize,
            'digest'       => asset.hexdigest,
            'integrity'    => asset.integrity
          }
          assets[asset.logical_path] = path

          target = File.join(dir, path)

          if File.exist?(target)
            logger.debug "Skipping #{target}, already exists"
          else
            logger.info "Writing #{target}"
            asset.write_to target
            asset.write_to File.join(dir,asset.logical_path) if digest_assets?
            asset.write_to "#{target}.gz" if compress_assets?
          end

          filenames << asset.filename
        end
        save

        filenames
      end
    end
  end
end
