require "rails_helper"

RSpec.describe Contribution, type: :model do
  let(:contribution) { register_key.then { |pair, _| Contribution.find_by!(signer_key_id: pair.key_id) } }

  it "gets a UUIDv7 id at append time" do
    expect(contribution.id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "allows only the cached status column to change" do
    expect(contribution.update(current_status: Contribution::CHALLENGED)).to be(true)
    expect { contribution.update!(payload: {}) }.to raise_error(Ledger::AppendOnlyViolation, /payload/)
    expect { contribution.update!(entry_hash: "sha256:#{'0' * 64}") }.to raise_error(Ledger::AppendOnlyViolation)
  end

  it "is never destroyed" do
    expect { contribution.destroy }.to raise_error(Ledger::AppendOnlyViolation)
  end

  it "renders received_at with microseconds in UTC" do
    expect(contribution.received_at_rfc3339).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z\z/)
  end

  # Stage 26: projection_rows asks only the tables an action type can write.
  describe "PROJECTIONS_BY_ACTION" do
    include GraphHelpers

    it "declares every action type, so a new one has to decide rather than inherit a guess" do
      expect(Contribution::PROJECTIONS_BY_ACTION.keys).to match_array(Ledger::ActionTypes::ALL)
    end

    it "covers every projection an applier creates" do
      Contribution::PROJECTIONS_BY_ACTION.each do |type, models|
        next if models.nil?

        file = Rails.root.join("app/services/ledger/appliers/#{type.downcase}.rb")
        next unless File.exist?(file)

        created = File.read(file).scan(/\b(#{Contribution::PROJECTION_MODELS.join('|')})\.(?:create|insert|upsert|new)\b/).flatten.uniq
        expect(created - models).to eq([]), "#{type} creates #{created - models} outside its declared tables"
      end
    end

    it "finds exactly the rows a search of every table finds, for every contribution the demos write" do
      release_models
      graph = build_public_demo
      build_watchers_demo
      # A null result: a task result with no ops writes no projection row.
      _, agent_pair, _, delegation = principal_with_agent
      task = create_task("OPPOSING_EVIDENCE_SEARCH", graph.claims.values.first)
      null = submit_result(agent_pair, task, delegation: delegation, outcome: "NONE_FOUND", ops: [], searched: "Looked; nothing.")
      expect(null.contribution.projection_tables).to eq([])
      checked = Contribution.find_each.count do |c|
        narrow = c.projection_rows.map { |r| [ r.class.name, r.id ] }.sort
        wide = c.projection_rows_everywhere.map { |r| [ r.class.name, r.id ] }.sort
        expect(narrow).to eq(wide), "#{c.action_type} at seq #{c.seq}"
      end
      expect(checked).to be > 100
      expect(Contribution.distinct.pluck(:action_type).size).to be >= 12
    end
  end
end
