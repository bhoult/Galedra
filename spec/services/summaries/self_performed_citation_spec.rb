require "rails_helper"

# A self-performed opposing search is recorded and shown but kept out of the
# review checklist (Stage 34). The summary input carries it as a task result,
# and the stub generator writes a sentence citing its task: that citation has to
# be one the validator accepts, or the claim page raises (2026-09-23).
RSpec.describe "Summary citations of a self-performed check" do
  it "lets the stub cite a task that is in the task results but not the checklist" do
    claim_id = SecureRandom.uuid_v7
    task_id = SecureRandom.uuid_v7
    input = {
      "claim" => { "id" => claim_id, "text" => "A claim.", "type" => "HISTORICAL" }, "model" => "ledger-default@0.3.0", "snapshot_seq" => 10,
      "assessment_state" => "INSUFFICIENT_EVIDENCE", "probability" => nil, "not_applicable_reason" => nil, "model_dependent" => false,
      "review_checklist" => { "opposing_search_done" => { "satisfied" => false, "by" => [] } }, "review_coverage" => "0.00",
      "kept" => [], "qualifiers" => [], "suppressed" => [], "related" => [], "audits" => [],
      "task_results" => [ { "task_id" => task_id, "task_type" => "OPPOSING_EVIDENCE_SEARCH", "outcome" => "NONE_FOUND" } ]
    }
    sentences = Summaries::StubGenerator.sentences(input, type: "STANDARD")
    expect(sentences.flat_map { |s| s["cites"] }).to include(task_id)
    expect { Summaries::Validator.validate!(sentences, input, type: "STANDARD") }.not_to raise_error
  end
end
