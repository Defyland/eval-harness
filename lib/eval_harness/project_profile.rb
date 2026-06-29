# frozen_string_literal: true

module EvalHarness
  class ProjectProfile
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
      return true if rails_app? && !ruby_gem?
      return false if ruby_gem?
      return false if ruby_tool?
      return false if operator_or_provider?

      http_service?
    end

    def http_service?
      readme = read("README.md").downcase
      return false if operator_or_provider?

      readme.match?(/\b(http|api|server|service|endpoint|railway)\b/)
    end

    def operator_or_provider?
      readme = read("README.md").downcase
      readme.include?("operator") || readme.include?("terraform provider")
    end

    def test_signal?
      dirs = %w[test spec tests]
      return true if dirs.any? { |dir| directory?(dir) }
      return true if file?("Makefile") && read("Makefile").match?(/^test:/)
      return true if file?("mix.exs") && read("mix.exs").include?("mix test")
      return true if file?("scripts/validate_curriculum.rb")

      false
    end

    def command_docs?
      read("README.md").match?(/^```(?:sh|bash|shell)\n.*?^```/m)
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

    def relative(path)
      path.delete_prefix("#{root}#{File::SEPARATOR}")
    end
  end
end
