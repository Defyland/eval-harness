# frozen_string_literal: true

module EvalHarness
  Rule = Struct.new(:id, :status, :message, :evidence, keyword_init: true) do
    def pass?
      status == "pass"
    end

    def fail?
      status == "fail"
    end

    def warning?
      status == "warn"
    end

    def not_applicable?
      status == "n/a"
    end

    def to_h
      {
        id: id,
        status: status,
        message: message,
        evidence: evidence
      }
    end
  end
end
