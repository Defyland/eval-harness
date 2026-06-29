# frozen_string_literal: true

require "fileutils"
require "optparse"

module EvalHarness
  class CLI
    def initialize(argv, stdout:, stderr:)
      @argv = argv
      @stdout = stdout
      @stderr = stderr
    end

    def call
      options = parse_options
      reports = options[:projects].map { |project| Evaluator.new(project).evaluate }
      output = render(reports, options[:format])

      if options[:output]
        FileUtils.mkdir_p(File.dirname(options[:output]))
        File.write(options[:output], output)
        @stdout.puts "Wrote #{options[:output]}"
      else
        @stdout.puts output
      end

      failed = reports.any? { |report| report[:summary][:fail].positive? }
      options[:fail_on] == "fail" && failed ? 1 : 0
    rescue OptionParser::ParseError, KeyError => error
      @stderr.puts "error: #{error.message}"
      @stderr.puts parser
      64
    end

    private

    def parse_options
      options = {
        format: "markdown",
        fail_on: "never"
      }

      parser(options).parse!(@argv)
      options[:projects] = @argv
      raise KeyError, "at least one project path is required" if options[:projects].empty?

      options
    end

    def parser(options = nil)
      @parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: eval-harness [options] PROJECT_PATH..."
        opts.on("--format FORMAT", "markdown or json") do |value|
          raise OptionParser::InvalidArgument, "format must be markdown or json" unless %w[markdown json].include?(value)

          options[:format] = value
        end
        opts.on("-o", "--output PATH", "Write report to PATH") do |value|
          options[:output] = value
        end
        opts.on("--fail-on VALUE", "never or fail") do |value|
          raise OptionParser::InvalidArgument, "fail-on must be never or fail" unless %w[never fail].include?(value)

          options[:fail_on] = value
        end
      end
    end

    def render(reports, format)
      case format
      when "json"
        JsonRenderer.new.render(reports)
      else
        MarkdownRenderer.new.render(reports)
      end
    end
  end
end
