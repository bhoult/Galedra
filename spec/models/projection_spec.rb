require "rails_helper"

RSpec.describe "Projections are written only by Ledger::Apply (07 Phase 2 #5)" do
  it "raises for every graph model outside Ledger.applying" do
    pair, = register_key
    source = create_source(pair)
    location = create_location(pair, source)
    claim = create_claim(pair, "A claim.")
    evidence = create_evidence(pair, location)
    link = link_evidence(pair, evidence, claim)
    group = create_group(pair)
    assignment = assign_group(pair, evidence, group)
    edge = create_edge(pair, claim, create_claim(pair, "Another."))

    [ source, location, claim, evidence, link, group, assignment, edge ].each do |row|
      expect { row.update!(created_seq: 0) }.to raise_error(ActiveRecord::ReadOnlyRecord), row.class.name
      expect { row.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord), row.class.name
    end
    expect { Claim.create!(id: SecureRandom.uuid, contribution_id: claim.contribution_id, canonical_text: "x", claim_type: "TEXTUAL", truth_evaluable: true, created_seq: 1) }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
