require "rails_helper"

RSpec.describe Tasks::Priority do
  it "computes the labelled heuristic from spec 03 §14" do
    expect(described_class.call(probability: nil, downstream_count: 0, review_coverage: "0.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("1.5000")
    expect(described_class.call(probability: "0.5000", downstream_count: 0, review_coverage: "1.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("0.5000")
    expect(described_class.call(probability: "0.9000", downstream_count: 0, review_coverage: "0.50", task_type: "OPPOSING_EVIDENCE_SEARCH", config: default_config)).to eq("0.0667")
    expect(described_class.call(probability: nil, downstream_count: 1, review_coverage: "0.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("2.5397")
  end

  # The heuristic above is spec 03 §14 and is deliberately left alone: it gives a
  # null probability maximum uncertainty, which is right for INSUFFICIENT_EVIDENCE.
  # The board damps NOT_APPLICABLE afterwards, the way it already damps by
  # priority_factor, because that one's outcome is fixed before the work starts.
  describe "on the board (experiment finding 10)" do
    include LedgerHelpers
    include GraphHelpers
    before { release_models }

    it "puts a NOT_APPLICABLE claim last rather than first, without closing the route" do
      pair, = register_key
      checkable = create_claim(pair, "Remote work raised measured output by 14% in the trial.", type: "QUANTITATIVE")
      unscorable = create_claim(pair, "Remote work ought to be the default everywhere.", type: "NORMATIVE")
      seq = Contribution.maximum(:seq)
      state = ->(c) { Scoring::Score.call(c, seq, Scoring::Registry.default_model).assessment_state }
      expect(state.call(unscorable)).to eq("NOT_APPLICABLE")
      expect(state.call(checkable)).to eq("INSUFFICIENT_EVIDENCE"), "both carry no probability, which is the whole trap"

      high = Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: checkable)
      low = Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: unscorable)

      expect(low.priority).to be < high.priority
      expect(low.priority).to eq(high.priority * BigDecimal(Tasks::Create::NOT_APPLICABLE_FACTOR))
      expect(low.status).to eq("OPEN"), "still openable: the type is a judgement a check can revise"
    end
  end
end
