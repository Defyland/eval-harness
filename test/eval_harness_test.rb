# frozen_string_literal: true

require "test_helper"
require "shellwords"

class EvalHarnessTest < Minitest::Test
  def test_ready_ruby_gem_passes_core_rules_without_railway_requirement
    Dir.mktmpdir do |dir|
      write_ready_gem(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "ruby-gem", report[:stack]
      refute report[:railway_recommended]
      assert_rule report, "docs.readme", "pass"
      assert_rule report, "docs.commands", "pass"
      assert_rule report, "docs.decisions", "pass"
      assert_rule report, "docs.architecture", "pass"
      assert_rule report, "quality.tests", "pass"
      assert_rule report, "quality.ci", "pass"
      assert_rule report, "ai.context_pack", "n/a"
      assert_rule report, "deploy.railway", "n/a"
      assert_rule report, "security.sensitive_files", "pass"
      assert_rule report, "project.manifest", "pass"
      assert_equal 0, report[:summary][:fail]
      refute report[:summary][:ready], "git warning means the project is not fully release-ready"
    end
  end

  def test_rails_app_with_sensitive_files_warns_about_railway_and_fails_security
    Dir.mktmpdir do |dir|
      write_rails_app(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "rails", report[:stack]
      assert report[:railway_recommended]
      assert_rule report, "deploy.railway", "warn"
      assert_rule report, "security.sensitive_files", "fail"
      secret_rule = report[:rules].find { |rule| rule[:id] == "security.sensitive_files" }
      assert_includes secret_rule[:evidence], "Rails master key present"
      refute report[:summary][:ready]
    end
  end

  def test_ignored_local_secret_passes_when_git_repo_exists
    Dir.mktmpdir do |dir|
      write_rails_app(dir)
      File.write(File.join(dir, ".gitignore"), "/config/*.key\n")
      init_git_repo(dir)
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "Initial import", out: File::NULL, err: File::NULL)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "security.sensitive_files", "pass"
    end
  end

  def test_tracked_kamal_secret_fails_even_when_it_is_safe_template_content
    Dir.mktmpdir do |dir|
      write_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, ".kamal"))
      File.write(File.join(dir, ".kamal/secrets"), "RAILS_MASTER_KEY=$(cat config/master.key)\n")
      init_git_repo(dir)
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "Initial import", out: File::NULL, err: File::NULL)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "security.sensitive_files", "fail"
      secret_rule = report[:rules].find { |rule| rule[:id] == "security.sensitive_files" }
      assert_includes secret_rule[:evidence], "Kamal secrets file present"
    end
  end

  def test_unignored_local_secret_warns_when_git_repo_exists
    Dir.mktmpdir do |dir|
      write_rails_app(dir)
      init_git_repo(dir)
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "Initial import", out: File::NULL, err: File::NULL)
      system("git", "-C", dir, "rm", "--cached", "config/master.key", out: File::NULL, err: File::NULL)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "security.sensitive_files", "warn"
      secret_rule = report[:rules].find { |rule| rule[:id] == "security.sensitive_files" }
      assert_includes secret_rule[:evidence], "Rails master key present"
    end
  end

  def test_weak_project_fails_essential_rules
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "README.md"), "# Weak\n")

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "docs.readme", "pass"
      assert_rule report, "docs.commands", "warn"
      assert_rule report, "docs.decisions", "fail"
      assert_rule report, "quality.tests", "fail"
      assert_rule report, "quality.ci", "fail"
      assert_rule report, "project.manifest", "fail"
      refute report[:summary][:ready]
    end
  end

  def test_study_content_repo_uses_curriculum_validation_instead_of_railway
    Dir.mktmpdir do |dir|
      write_study_content(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "study-content", report[:stack]
      refute report[:railway_recommended]
      assert_rule report, "quality.tests", "pass"
      assert_rule report, "docs.architecture", "pass"
      assert_rule report, "deploy.railway", "n/a"
    end
  end

  def test_ruby_tool_does_not_require_railway
    Dir.mktmpdir do |dir|
      write_ruby_tool(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "ruby-tool", report[:stack]
      refute report[:railway_recommended]
      assert_rule report, "ai.context_pack", "n/a"
      assert_rule report, "deploy.railway", "n/a"
    end
  end

  def test_cli_go_tool_does_not_require_railway
    Dir.mktmpdir do |dir|
      write_cli_go_tool(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "go", report[:stack]
      refute report[:railway_recommended]
      assert_rule report, "deploy.railway", "n/a"
    end
  end

  def test_competition_asset_does_not_require_railway_even_when_it_is_a_rails_app
    Dir.mktmpdir do |dir|
      write_competition_rails_app(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_equal "rails", report[:stack]
      refute report[:railway_recommended]
      assert_rule report, "deploy.railway", "n/a"
    end
  end

  def test_recursive_go_test_file_counts_as_test_surface
    Dir.mktmpdir do |dir|
      write_go_bootstrap(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "quality.tests", "pass"
      rule = report[:rules].find { |candidate| candidate[:id] == "quality.tests" }
      assert_includes rule[:evidence], "internal/bootstrapapi/handler_test.go"
    end
  end

  def test_research_root_contract_counts_as_test_surface_and_skips_railway
    Dir.mktmpdir do |dir|
      write_research_asset(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "quality.tests", "pass"
      assert_rule report, "deploy.railway", "n/a"
      rule = report[:rules].find { |candidate| candidate[:id] == "quality.tests" }
      assert_includes rule[:evidence], "bin/check"
    end
  end

  def test_missing_workspace_context_pack_warns_when_registry_exists
    Dir.mktmpdir do |workspace|
      dir = File.join(workspace, "ruby-tool")
      FileUtils.mkdir_p(File.join(workspace, ".agents/context-packs"))
      write_ruby_tool(dir)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "ai.context_pack", "warn"
      rule = report[:rules].find { |candidate| candidate[:id] == "ai.context_pack" }
      assert_includes rule[:evidence], ".agents/context-packs/ruby-tool.md"
    end
  end

  def test_stale_workspace_context_pack_warns_when_project_is_newer_than_pack
    Dir.mktmpdir do |workspace|
      dir = File.join(workspace, "ready-gem")
      FileUtils.mkdir_p(File.join(workspace, ".agents/context-packs"))
      write_ready_gem(dir)
      init_git_repo(dir)
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "Initial import", out: File::NULL, err: File::NULL)

      pack = File.join(workspace, ".agents/context-packs", "ready-gem.md")
      File.write(pack, "# Context Pack\n")
      File.utime(Time.at(1), Time.at(1), pack)

      File.write(File.join(dir, "README.md"), <<~README)
        # Ready Gem

        ```sh
        bundle exec rake test
        ```

        Updated after context pack generation.
      README
      system("git", "-C", dir, "add", "README.md")
      system("git", "-C", dir, "commit", "-m", "Update readme", out: File::NULL, err: File::NULL)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "ai.context_pack", "warn"
      rule = report[:rules].find { |candidate| candidate[:id] == "ai.context_pack" }
      assert_includes rule[:evidence], ".agents/context-packs/ready-gem.md"
      assert_includes rule[:message], "older than the latest commit"
    end
  end

  def test_context_pack_with_matching_commit_metadata_passes_even_when_file_mtime_is_old
    Dir.mktmpdir do |workspace|
      dir = File.join(workspace, "ready-gem")
      FileUtils.mkdir_p(File.join(workspace, ".agents/context-packs"))
      write_ready_gem(dir)
      init_git_repo(dir)
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "Initial import", out: File::NULL, err: File::NULL)
      commit_sha = `git -C #{Shellwords.escape(dir)} log -1 --format=%H`.strip

      pack = File.join(workspace, ".agents/context-packs", "ready-gem.md")
      File.write(pack, <<~PACK)
        <!-- context-pack-builder-meta {"project":"ready-gem","generated_at":"2026-06-29T12:00:00Z","git_commit":"#{commit_sha}","git_branch":"main"} -->
        # Context Pack: ready-gem
      PACK
      File.utime(Time.at(1), Time.at(1), pack)

      report = EvalHarness::Evaluator.new(dir).evaluate

      assert_rule report, "ai.context_pack", "pass"
    end
  end


  def test_cli_outputs_json_and_returns_failure_when_fail_on_fail_is_enabled
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "README.md"), "# Weak\n")
      output = File.join(dir, "report.json")
      stdout = StringIO.new
      stderr = StringIO.new

      status = EvalHarness::CLI.new([dir, "--format", "json", "--output", output, "--fail-on", "fail"], stdout: stdout, stderr: stderr).call

      assert_equal 1, status
      parsed = JSON.parse(File.read(output))
      assert_equal File.basename(dir), parsed.fetch("reports").first.fetch("name")
      assert_includes stdout.string, "Wrote #{output}"
      assert_empty stderr.string
    end
  end

  def test_markdown_renderer_includes_summary_table
    Dir.mktmpdir do |dir|
      write_ready_gem(dir)
      report = EvalHarness::Evaluator.new(dir).evaluate

      markdown = EvalHarness::MarkdownRenderer.new.render([report])

      assert_includes markdown, "# AI-Ready Evaluation Report"
      assert_includes markdown, "| `#{File.basename(dir)}` | ruby-gem | no |"
      assert_includes markdown, "| `deploy.railway` | n/a |"
    end
  end

  private

  def assert_rule(report, id, status)
    rule = report[:rules].find { |candidate| candidate[:id] == id }
    refute_nil rule, "expected rule #{id}"
    assert_equal status, rule[:status], "expected #{id} to be #{status}: #{rule.inspect}"
  end

  def write_ready_gem(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Ready Gem

      ```sh
      bundle exec rake test
      ```
    README
    File.write(File.join(dir, "ready_gem.gemspec"), "Gem::Specification.new\n")
    File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(dir, "Rakefile"), "task default: :test\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/engineering-case-study.md"), "# Case Study\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def write_rails_app(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "config"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Rails App

      ```sh
      bin/rails test
      ```
    README
    File.write(File.join(dir, "Gemfile"), "gem 'rails'\n")
    File.write(File.join(dir, "config/application.rb"), "module App; class Application; end; end\n")
    File.write(File.join(dir, "config/master.key"), "do-not-copy\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def init_git_repo(dir)
    system("git", "-C", dir, "init", "-q")
    system("git", "-C", dir, "config", "user.name", "Eval Harness")
    system("git", "-C", dir, "config", "user.email", "eval@example.com")
  end

  def write_cli_go_tool(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "cmd/tokenforge"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    File.write(File.join(dir, "README.md"), <<~README)
      # TokenForge

      This is a command-line product.

      It has no HTTP API and is not a daemon.

      ```sh
      go test ./...
      ```
    README
    File.write(File.join(dir, "go.mod"), "module example.com/tokenforge\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/engineering-case-study.md"), "# Case Study\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def write_competition_rails_app(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "config"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Competition Rails App

      ```sh
      bin/rails test
      ```

      API-only bootstrap for a competition environment.
    README
    File.write(File.join(dir, "Gemfile"), "gem 'rails'\n")
    File.write(File.join(dir, "config/application.rb"), "module App; class Application; end; end\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/architecture.md"), "# Architecture\n")
    File.write(File.join(dir, "docs/competition-constraints.md"), "# Constraints\n")
    File.write(File.join(dir, "test/bootstrap_test.rb"), "assert true\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def write_go_bootstrap(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "internal/bootstrapapi"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Go Bootstrap

      ```sh
      go test ./...
      ```
    README
    File.write(File.join(dir, "go.mod"), "module example.com/bootstrap\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/architecture.md"), "# Architecture\n")
    File.write(File.join(dir, "internal/bootstrapapi/handler_test.go"), "package bootstrapapi\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def write_research_asset(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "bin"))
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Research Asset

      R&D asset and falsification experiment.

      This is not a deployable service.

      ```sh
      bin/check
      ```
    README
    File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/architecture.md"), "# Architecture\n")
    File.write(File.join(dir, "bin/check"), "#!/usr/bin/env ruby\n")
    File.write(File.join(dir, "lib/experiment.rb"), "# frozen_string_literal: true\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end

  def write_study_content(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "scripts"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Study Content

      ```sh
      ruby scripts/validate_curriculum.rb
      ```
    README
    File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(dir, "curriculum.yml"), "---\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "CASE_DRIVEN_STUDY.md"), "# Study Method\n")
    File.write(File.join(dir, "scripts/validate_curriculum.rb"), "puts 'ok'\n")
    File.write(File.join(dir, ".github/workflows/curriculum.yml"), "name: Curriculum\n")
  end

  def write_ruby_tool(dir)
    FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
    FileUtils.mkdir_p(File.join(dir, "bin"))
    FileUtils.mkdir_p(File.join(dir, "docs"))
    FileUtils.mkdir_p(File.join(dir, "lib"))
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "README.md"), <<~README)
      # Ruby Tool

      ```sh
      bundle exec rake test
      ```
    README
    File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(dir, "Rakefile"), "task default: :test\n")
    File.write(File.join(dir, "docs/decisions.md"), "# Decisions\n")
    File.write(File.join(dir, "docs/architecture.md"), "# Architecture\n")
    File.write(File.join(dir, "bin/tool"), "#!/usr/bin/env ruby\n")
    File.write(File.join(dir, "lib/tool.rb"), "# frozen_string_literal: true\n")
    File.write(File.join(dir, ".github/workflows/ci.yml"), "name: CI\n")
  end
end
