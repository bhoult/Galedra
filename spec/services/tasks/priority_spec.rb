require "rails_helper"

RSpec.describe Tasks::Priority do
  it "computes the labelled heuristic from spec 03 §14" do
    expect(described_class.call(probability: nil, downstream_count: 0, review_coverage: "0.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("1.5000")
    expect(described_class.call(probability: "0.5000", downstream_count: 0, review_coverage: "1.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("0.5000")
    expect(described_class.call(probability: "0.9000", downstream_count: 0, review_coverage: "0.50", task_type: "OPPOSING_EVIDENCE_SEARCH", config: default_config)).to eq("0.0667")
    expect(described_class.call(probability: nil, downstream_count: 1, review_coverage: "0.00", task_type: "EVIDENCE_VERIFICATION", config: default_config)).to eq("2.5397")
  end
end
