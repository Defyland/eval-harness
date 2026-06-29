# frozen_string_literal: true

module EvalHarness
  class MarkdownRenderer
    def render(reports)
      reports = Array(reports)
      lines = ["# AI-Ready Evaluation Report", ""]
      lines << summary_table(reports)
      lines << ""
      reports.each do |report|
        lines.concat(project_section(report))
      end
      lines.join("\n")
    end

    private

    def summary_table(reports)
      rows = [
        "| Project | Stack | Ready | Pass | Warn | Fail |",
        "| --- | --- | --- | ---: | ---: | ---: |"
      ]
      reports.each do |report|
        summary = report[:summary]
        rows << "| `#{report[:name]}` | #{report[:stack]} | #{summary[:ready] ? "yes" : "no"} | #{summary[:pass]} | #{summary[:warn]} | #{summary[:fail]} |"
      end
      rows.join("\n")
    end

    def project_section(report)
      lines = []
      lines << "## #{report[:name]}"
      lines << ""
      lines << "- Root: `#{report[:root]}`"
      lines << "- Stack: `#{report[:stack]}`"
      lines << "- Railway recommended: `#{report[:railway_recommended]}`"
      lines << "- Git: #{git_line(report[:git])}"
      lines << ""
      lines << "| Rule | Status | Message | Evidence |"
      lines << "| --- | --- | --- | --- |"
      report[:rules].each do |rule|
        evidence = rule[:evidence].empty? ? "" : rule[:evidence].map { |item| "`#{item}`" }.join(", ")
        lines << "| `#{rule[:id]}` | #{rule[:status]} | #{rule[:message]} | #{evidence} |"
      end
      lines << ""
      lines
    end

    def git_line(git)
      return "not initialized" unless git[:available]

      git[:clean] ? "clean" : "dirty: #{git[:status].map { |item| "`#{item}`" }.join(", ")}"
    end
  end
end
