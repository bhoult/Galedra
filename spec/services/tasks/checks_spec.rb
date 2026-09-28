require "rails_helper"

# Tasks::Checks.for runs on every cold score of a single claim. It asked whether
# each result was self-performed one result at a time, which on galedra.org's
# first day was 39,459 statements (pg_stat_statements, 2026-09-28). The
# number of statements must not grow with the number of results.
RSpec.describe Tasks::Checks do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }

  def statements
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  def claim_checked_by(answers)
    claim = create_claim(curator, "Remote work raised output by #{answers} per cent.", type: "QUANTITATIVE")
    task = create_task("QUALIFIER_CHECK", claim, required_assignments: 3)
    answers.times do
      _, agent_pair, _, delegation = principal_with_agent
      submit_result(agent_pair, task, delegation: delegation, outcome: "NONE_MATERIAL", ops: [])
    end
    claim
  end

  it "asks the same number of statements however many results a claim has" do
    one = claim_checked_by(1)
    three = claim_checked_by(3)
    seq = Contribution.maximum(:seq)

    expect(described_class.for(three.id, seq).size).to eq(3), "three independent answers, three checks"
    expect(described_class.for(one.id, seq).size).to eq(1)
    expect(statements { described_class.for(three.id, seq) }).to eq(statements { described_class.for(one.id, seq) })
  end
end
