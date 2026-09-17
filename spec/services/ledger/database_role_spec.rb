require "rails_helper"

RSpec.describe Ledger::DatabaseRole do
  let(:contribution) { register_key.then { |pair, _| Contribution.find_by!(signer_key_id: pair.key_id) } }

  it "runs the application as the restricted role" do
    expect(Contribution.connection.select_value("SELECT current_user")).to eq(described_class::ROLE)
  end

  it "forbids DELETE, TRUNCATE, and non-status UPDATE on contributions (append-only DB permissions)" do
    id = contribution.id
    forbidden = [
      "DELETE FROM contributions WHERE id = '#{id}'",
      "TRUNCATE contributions",
      "UPDATE contributions SET payload = '{}' WHERE id = '#{id}'",
      "UPDATE contributions SET entry_hash = 'x' WHERE id = '#{id}'"
    ]
    forbidden.each do |sql|
      expect { Contribution.transaction(requires_new: true) { Contribution.connection.execute(sql) } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/), sql
    end
  end

  it "allows the cached status column to change and rows to be appended" do
    Contribution.connection.execute("UPDATE contributions SET current_status = 'CHALLENGED' WHERE id = '#{contribution.id}'")
    expect(contribution.reload.current_status).to eq("CHALLENGED")
    expect(Contribution.count).to be > 1
  end

  it "can truncate projections for replay" do
    expect { Contribution.transaction(requires_new: true) { Contribution.connection.execute("TRUNCATE contributors, agent_delegations") } }.not_to raise_error
  end
end
