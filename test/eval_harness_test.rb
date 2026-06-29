# frozen_string_literal: true

require "test_helper"

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
      assert_rule report, "deploy.railway", "n/a"
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
