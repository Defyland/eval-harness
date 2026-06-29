# frozen_string_literal: true

require "open3"

module EvalHarness
  class GitSnapshot
    def initialize(project_root)
      @project_root = project_root
    end

    def to_h
      return {available: false, clean: nil, status: [], recent_commits: []} unless File.directory?(File.join(@project_root, ".git"))

      status = capture("git", "status", "--short").lines.map(&:chomp)
      {
        available: true,
        clean: status.empty?,
        status: status,
        recent_commits: capture("git", "log", "--oneline", "-n", "5").lines.map(&:chomp)
      }
    end

    private

    def capture(*command)
      stdout, _stderr, status = Open3.capture3(*command, chdir: @project_root)
      status.success? ? stdout : ""
    end
  end
end
