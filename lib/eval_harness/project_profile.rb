# frozen_string_literal: true

require "json"
require "open3"

module EvalHarness
  class ProjectProfile
    CONTEXT_PACKS_DIR = File.join(".agents", "context-packs").freeze
    CONTEXT_PACK_METADATA_PREFIX = "<!-- context-pack-builder-meta ".freeze
    EXCLUDED_GLOB_DIRS = %w[.bundle .git .gocache coverage dist log node_modules pkg tmp vendor].freeze
    TEST_GLOBS = [
      "**/*_test.rb",
      "**/*_spec.rb",
      "**/*_test.go",
      "**/*_test.exs",
      "**/*_test.ex",
      "tests/**/*.rs"
    ].freeze
    ROOT_VERIFICATION_COMMANDS = %w[bin/check bin/ci].freeze

    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)
    end

    def name
      File.basename(root)
    end

    def rails_app?
      file?("config/application.rb") && file?("Gemfile")
    end

    def ruby_gem?
      !Dir.glob(File.join(root, "*.gemspec")).empty?
    end

    def go_project?
      file?("go.mod")
    end

    def rust_project?
      file?("Cargo.toml")
    end

    def elixir_project?
      file?("mix.exs")
    end

    def node_project?
      file?("package.json")
    end

    def ruby_tool?
      file?("Gemfile") && directory?("lib") && directory?("bin") && !rails_app? && !ruby_gem?
    end

    def study_content?
      file?("curriculum.yml") && directory?("chapters")
    end

    def stack
      return "study-content" if study_content?
      return "rails" if rails_app?
      return "ruby-gem" if ruby_gem?
      return "ruby-tool" if ruby_tool?
      return "go" if go_project?
      return "rust" if rust_project?
      return "elixir" if elixir_project?
      return "node" if node_project?

      "unknown"
    end

    def railway_recommended?
      return false if study_content?
      return false if competition_asset?
      return false if research_asset?
      return false if cli_only_product?
      return true if rails_app? && !ruby_gem?
      return false if ruby_gem?
      return false if ruby_tool?
      return false if operator_or_provider?

      http_service?
    end

    def http_service?
      return false if operator_or_provider? || competition_asset? || research_asset? || cli_only_product?

      readme_text.match?(/\b(http|api|server|service|endpoint|railway)\b/)
    end

    def operator_or_provider?
      readme_text.include?("operator") || readme_text.include?("terraform provider")
    end

    def competition_asset?
      file?("docs/competition-constraints.md")
    end

    def research_asset?
      readme_text.include?("r&d asset") ||
        readme_text.include?("falsification experiment") ||
        readme_text.include?("not a deployable service")
    end

    def cli_only_product?
      cli_signal = readme_text.match?(/\b(cli|command-line)\b/)
      non_http_signal = readme_text.include?("no http api") || readme_text.include?("not a daemon")
      cli_signal && non_http_signal
    end

    def test_signal?
      dirs = %w[test spec tests]
      return true if dirs.any? { |dir| directory?(dir) }
      return true if test_files.any? || verified_root_contracts.any?
      return true if file?("Makefile") && read("Makefile").match?(/^test:/)
      return true if file?("mix.exs") && read("mix.exs").include?("mix test")
      return true if file?("scripts/validate_curriculum.rb")

      false
    end

    def command_docs?
      !command_snippets.empty?
    end

    def ci_files
      Dir.glob(File.join(root, ".github/workflows/*.{yml,yaml}")).map { |path| relative(path) }.sort
    end

    def decisions_files
      files = []
      files << "docs/decisions.md" if file?("docs/decisions.md")
      files.concat(Dir.glob(File.join(root, "docs/adr/*.{md,markdown}")).map { |path| relative(path) })
      files.sort
    end

    def architecture_files
      candidates = [
        "docs/architecture.md",
        "docs/architecture/overview.md",
        "docs/engineering-case-study.md",
        "CASE_DRIVEN_STUDY.md",
        "COURSE_OUTLINE.md"
      ]
      candidates.select { |path| file?(path) }
    end

    def test_evidence
      evidence = []
      evidence << "test/" if directory?("test")
      evidence << "spec/" if directory?("spec")
      evidence << "tests/" if directory?("tests")
      evidence.concat(test_files.first(4))
      evidence.concat(verified_root_contracts)
      evidence << "Makefile test target" if file?("Makefile") && read("Makefile").match?(/^test:/)
      evidence << "mix.exs" if file?("mix.exs")
      evidence << "scripts/validate_curriculum.rb" if file?("scripts/validate_curriculum.rb")
      evidence.uniq
    end

    def context_pack_applicable?
      !context_pack_registry_root.nil?
    end

    def context_pack_relative_path
      File.join(CONTEXT_PACKS_DIR, "#{name}.md")
    end

    def context_pack_present?
      !context_pack_path.nil?
    end

    def context_pack_stale?
      return false unless context_pack_present?

      commit_sha = latest_commit_sha
      metadata_commit = context_pack_generated_commit
      return metadata_commit != commit_sha if commit_sha && metadata_commit

      commit_timestamp = latest_commit_timestamp
      return false unless commit_timestamp

      File.mtime(context_pack_path).to_i < commit_timestamp
    end

    def context_pack_generated_commit
      context_pack_metadata&.fetch("git_commit", nil)
    end

    def secret_warnings
      secret_findings.map { |finding| finding.fetch(:message) }
    end

    def secret_findings
      findings = []
      append_secret_finding(findings, ".env", ".env present")
      append_secret_finding(findings, "config/master.key", "Rails master key present")
      append_secret_finding(findings, ".kamal/secrets", "Kamal secrets file present")
      findings
    end

    def manifest_files
      %w[Gemfile go.mod Cargo.toml mix.exs package.json Dockerfile railway.json openapi.yaml openapi.yml].select { |path| file?(path) }
    end

    def file?(path)
      File.file?(File.join(root, path))
    end

    def directory?(path)
      File.directory?(File.join(root, path))
    end

    def read(path)
      absolute = File.join(root, path)
      return "" unless File.file?(absolute)

      File.read(absolute, mode: "r:BOM|UTF-8")
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      ""
    end

    private

    def readme_text
      @readme_text ||= read("README.md").downcase
    end

    def command_snippets
      @command_snippets ||= read("README.md").scan(/^```(?:sh|bash|shell)\n(.*?)^```/m).flatten.map(&:strip).reject(&:empty?)
    end

    def test_files
      @test_files ||= TEST_GLOBS.flat_map { |pattern| Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH) }
        .select { |path| File.file?(path) }
        .reject { |path| excluded_glob_path?(path) }
        .map { |path| relative(path) }
        .sort
    end

    def verified_root_contracts
      @verified_root_contracts ||= ROOT_VERIFICATION_COMMANDS.select do |path|
        file?(path) && command_snippets.any? { |snippet| snippet.match?(/(^|\s)#{Regexp.escape(path)}(\s|$)/) }
      end
    end

    def excluded_glob_path?(absolute_path)
      parts = relative(absolute_path).split(File::SEPARATOR)
      (parts & EXCLUDED_GLOB_DIRS).any?
    end

    def append_secret_finding(findings, path, message)
      return unless file?(path)

      status = secret_file_status(path)
      return if status == "pass"

      findings << {status: status, message: message}
    end

    def secret_file_status(path)
      return "fail" unless git_available?
      return "fail" if tracked_file?(path)
      return "warn" unless ignored_file?(path)

      "pass"
    end

    def git_available?
      system("git", "-C", root, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
    end

    def tracked_file?(path)
      system("git", "-C", root, "ls-files", "--error-unmatch", path, out: File::NULL, err: File::NULL)
    end

    def ignored_file?(path)
      system("git", "-C", root, "check-ignore", "-q", path, out: File::NULL, err: File::NULL)
    end

    def context_pack_registry_root
      return @context_pack_registry_root if defined?(@context_pack_registry_root)

      current = root
      loop do
        if File.directory?(File.join(current, CONTEXT_PACKS_DIR))
          @context_pack_registry_root = current
          return @context_pack_registry_root
        end

        parent = File.dirname(current)
        break if parent == current

        current = parent
      end

      @context_pack_registry_root = nil
    end

    def context_pack_path
      return nil unless context_pack_applicable?

      absolute = File.join(context_pack_registry_root, context_pack_relative_path)
      File.file?(absolute) ? absolute : nil
    end

    def context_pack_metadata
      return @context_pack_metadata if defined?(@context_pack_metadata)
      return @context_pack_metadata = nil unless context_pack_present?

      first_line = File.open(context_pack_path, "r:BOM|UTF-8", &:gets).to_s.strip
      unless first_line.start_with?(CONTEXT_PACK_METADATA_PREFIX) && first_line.end_with?(" -->")
        return @context_pack_metadata = nil
      end

      payload = first_line.delete_prefix(CONTEXT_PACK_METADATA_PREFIX).delete_suffix(" -->")
      @context_pack_metadata = JSON.parse(payload)
    rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      @context_pack_metadata = nil
    end

    def latest_commit_timestamp
      return nil unless git_available?

      timestamp = capture_git("log", "-1", "--format=%ct").strip
      return nil if timestamp.empty?

      timestamp.to_i
    end

    def latest_commit_sha
      return nil unless git_available?

      sha = capture_git("log", "-1", "--format=%H").strip
      return nil if sha.empty?

      sha
    end

    def capture_git(*args)
      stdout, _stderr, status = Open3.capture3("git", "-C", root, *args)
      status.success? ? stdout : ""
    end

    def relative(path)
      path.delete_prefix("#{root}#{File::SEPARATOR}")
    end
  end
end
