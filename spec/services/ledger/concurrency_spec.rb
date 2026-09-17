require "rails_helper"

RSpec.describe "Concurrent appends (07 Phase 1 #3)" do
  self.use_transactional_tests = false

  after do
    as_owner { Contribution.where("seq > 0").delete_all }
    Contributor.where.not(kind: Contributor::SYSTEM).delete_all
    AgentDelegation.delete_all
  end

  it "produce a gap-free seq and a valid chain from 50 threads" do
    start = Contribution.maximum(:seq)
    contributors_before = Contributor.count
    errors = Queue.new
    threads = Array.new(50) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          register_key(display_name: "thread-#{i}")
        end
      rescue => e
        errors << e
      end
    end
    threads.each(&:join)

    expect(errors.size).to eq(0), -> { errors.size.times.map { errors.pop.message }.join("\n") }
    seqs = Contribution.where("seq > ?", start).in_order.pluck(:seq)
    expect(seqs).to eq(((start + 1)..(start + 50)).to_a)
    expect(Contributor.count - contributors_before).to eq(50)
    expect(Ledger::Verify.call.status).to eq(Ledger::Verify::CHAIN_VERIFIED)
  end
end
