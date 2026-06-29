# frozen_string_literal: true

module EvalHarness
  class Evaluator
    def initialize(project_root)
      @profile = ProjectProfile.new(project_root)
      @git = GitSnapshot.new(@profile.root).to_h
    end

    def evaluate
      {
        name: @profile.name,
        root: @profile.root,
        stack: @profile.stack,
        railway_recommended: @profile.railway_recommended?,
        git: @git,
        rules: rules.map(&:to_h),
        summary: summary
      }
    end

    private

    def rules
      @rules ||= [
        readme_rule,
        command_docs_rule,
        decisions_rule,
        architecture_rule,
        tests_rule,
        ci_rule,
        context_pack_rule,
        railway_rule,
        secret_rule,
        git_rule,
        manifest_rule
      ]
    end

    def summary
      counts = rules.group_by(&:status).transform_values(&:count)
      {
        pass: counts.fetch("pass", 0),
        warn: counts.fetch("warn", 0),
        fail: counts.fetch("fail", 0),
        not_applicable: counts.fetch("n/a", 0),
        ready: counts.fetch("fail", 0).zero? && counts.fetch("warn", 0).zero?
      }
    end

    def readme_rule
      if @profile.file?("README.md")
        Rule.new(id: "docs.readme", status: "pass", message: "README exists", evidence: ["README.md"])
      else
        Rule.new(id: "docs.readme", status: "fail", message: "README is required for AI-operable context", evidence: [])
      end
    end

    def command_docs_rule
      if @profile.command_docs?
        Rule.new(id: "docs.commands", status: "pass", message: "README includes shell command snippets", evidence: ["README.md"])
      else
        Rule.new(id: "docs.commands", status: "warn", message: "README should include runnable shell commands", evidence: [])
      end
    end

    def decisions_rule
      files = @profile.decisions_files
      if files.empty?
        Rule.new(id: "docs.decisions", status: "fail", message: "Technical decisions must be documented with tradeoffs", evidence: [])
      else
        Rule.new(id: "docs.decisions", status: "pass", message: "Decision documentation exists", evidence: files)
      end
    end

    def architecture_rule
      files = @profile.architecture_files
      if files.empty?
        Rule.new(id: "docs.architecture", status: "warn", message: "Architecture or engineering case study is missing", evidence: [])
      else
        Rule.new(id: "docs.architecture", status: "pass", message: "Architecture or case-study docs exist", evidence: files)
      end
    end

    def tests_rule
      if @profile.test_signal?
        Rule.new(id: "quality.tests", status: "pass", message: "Test surface detected", evidence: test_evidence)
      else
        Rule.new(id: "quality.tests", status: "fail", message: "Tests or a test command are required", evidence: [])
      end
    end

    def ci_rule
      files = @profile.ci_files
      if files.empty?
        Rule.new(id: "quality.ci", status: "fail", message: "GitHub Actions CI is required", evidence: [])
      else
        Rule.new(id: "quality.ci", status: "pass", message: "CI workflows detected", evidence: files)
      end
    end

    def context_pack_rule
      return Rule.new(
        id: "ai.context_pack",
        status: "n/a",
        message: "No workspace context-pack registry detected",
        evidence: []
      ) unless @profile.context_pack_applicable?

      evidence = [@profile.context_pack_relative_path]

      unless @profile.context_pack_present?
        return Rule.new(
          id: "ai.context_pack",
          status: "warn",
          message: "Workspace context pack is missing",
          evidence: evidence
        )
      end

      if @profile.context_pack_stale?
        evidence << @git[:recent_commits].first if @git[:recent_commits].first
        Rule.new(
          id: "ai.context_pack",
          status: "warn",
          message: "Workspace context pack is older than the latest commit",
          evidence: evidence
        )
      else
        Rule.new(
          id: "ai.context_pack",
          status: "pass",
          message: "Workspace context pack exists and is current enough for review",
          evidence: evidence
        )
      end
    end

    def railway_rule
      if @profile.railway_recommended?
        if @profile.file?("railway.json") || @profile.file?("RAILWAY_DEPLOY.md")
          Rule.new(id: "deploy.railway", status: "pass", message: "Railway deployment surface exists", evidence: railway_evidence)
        else
          Rule.new(id: "deploy.railway", status: "warn", message: "Railway is recommended for this runnable service but not detected", evidence: [])
        end
      else
        Rule.new(id: "deploy.railway", status: "n/a", message: "Railway not required for this project shape", evidence: [])
      end
    end

    def secret_rule
      findings = @profile.secret_findings
      if findings.empty?
        Rule.new(id: "security.sensitive_files", status: "pass", message: "No common sensitive local files detected", evidence: [])
      elsif findings.any? { |finding| finding.fetch(:status) == "fail" }
        Rule.new(
          id: "security.sensitive_files",
          status: "fail",
          message: "Sensitive files are tracked or otherwise publishable",
          evidence: findings.map { |finding| finding.fetch(:message) }
        )
      else
        Rule.new(
          id: "security.sensitive_files",
          status: "warn",
          message: "Sensitive local files exist but are not currently publishable",
          evidence: findings.map { |finding| finding.fetch(:message) }
        )
      end
    end

    def git_rule
      if !@git[:available]
        Rule.new(id: "release.git", status: "warn", message: "Git repository is not initialized", evidence: [])
      elsif @git[:clean]
        Rule.new(id: "release.git", status: "pass", message: "Git worktree is clean", evidence: @git[:recent_commits])
      else
        Rule.new(id: "release.git", status: "warn", message: "Git worktree has local changes", evidence: @git[:status])
      end
    end

    def manifest_rule
      files = @profile.manifest_files
      if files.empty?
        Rule.new(id: "project.manifest", status: "fail", message: "No recognized project manifest found", evidence: [])
      else
        Rule.new(id: "project.manifest", status: "pass", message: "Project manifests detected", evidence: files)
      end
    end

    def test_evidence
      evidence = []
      evidence << "test/" if @profile.directory?("test")
      evidence << "spec/" if @profile.directory?("spec")
      evidence << "tests/" if @profile.directory?("tests")
      evidence << "Makefile test target" if @profile.file?("Makefile") && @profile.read("Makefile").match?(/^test:/)
      evidence << "mix.exs" if @profile.file?("mix.exs")
      evidence << "scripts/validate_curriculum.rb" if @profile.file?("scripts/validate_curriculum.rb")
      evidence
    end

    def railway_evidence
      evidence = []
      evidence << "railway.json" if @profile.file?("railway.json")
      evidence << "RAILWAY_DEPLOY.md" if @profile.file?("RAILWAY_DEPLOY.md")
      evidence
    end
  end
end
