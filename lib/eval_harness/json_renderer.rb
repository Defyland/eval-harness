# frozen_string_literal: true

require "json"

module EvalHarness
  class JsonRenderer
    def render(reports)
      JSON.pretty_generate({reports: Array(reports)})
    end
  end
end
