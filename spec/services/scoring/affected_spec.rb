require "rails_helper"

RSpec.describe "Incremental recompute (07 Phase 3 acceptance #5)" do
  include ActiveJob::TestHelper

  before { release_models }

  it "recomputes only the claims a contribution touched" do
    curator, = register_key
    source = create_source(curator)
    location = create_location(curator, source)
    a = create_claim(curator, "Claim A.")
    b = create_claim(curator, "Claim B.")
    untouched = create_claim(curator, "Untouched.")
    ea = create_evidence(curator, location, statement: "for A")
    eb = create_evidence(curator, location, statement: "for B")
    link_a = link_evidence(curator, ea, a)
    link_evidence(curator, eb, b)

    expect(Scoring::Affected.claim_ids(link_a.contribution)).to eq([ a.id ])
    expect(Scoring::Affected.claim_ids(ea.contribution)).to eq([ a.id ])
    expect(Scoring::Affected.claim_ids(location.contribution)).to contain_exactly(a.id, b.id)
    expect(Scoring::Affected.claim_ids(untouched.contribution)).to eq([ untouched.id ])

    group = create_group(curator)
    assignment = assign_group(curator, ea, group)
    expect(Scoring::Affected.claim_ids(assignment.contribution)).to eq([ a.id ])
    accept_of_link = Contribution.find_by!(action_type: "ACCEPT", payload: { "contribution_id" => link_a.contribution_id, "basis" => "AUTOMATIC_AFTER_VALIDATION" })
    expect(Scoring::Affected.claim_ids(accept_of_link)).to eq([ a.id ])

    ClaimScore.delete_all
    RecomputeAffectedScoresJob.perform_now(link_a.contribution.seq)
    expect(ClaimScore.pluck(:claim_id).uniq).to eq([ a.id ])
    expect(ClaimScore.where(claim_id: a.id, snapshot_seq: link_a.contribution.seq).count).to eq(Scoring::Registry.released.count)
    expect { RecomputeAffectedScoresJob.perform_now(link_a.contribution.seq) }.not_to change(ClaimScore, :count)
  end

  it "enqueues a recompute for score-affecting appends only" do
    curator, = register_key
    clear_enqueued_jobs
    claim = create_claim(curator, "Enqueue me.")
    expect(enqueued_jobs.map { |j| j["job_class"] }).to include("RecomputeAffectedScoresJob")
    expect(enqueued_jobs.map { |j| j["arguments"].first }).to include(claim.contribution.seq)

    clear_enqueued_jobs
    register_key
    expect(enqueued_jobs.map { |j| j["job_class"] }).not_to include("RecomputeAffectedScoresJob")
  end
end
