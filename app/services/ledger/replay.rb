# frozen_string_literal: true

module Ledger
  # Truncates every projection and re-applies the log in seq order (spec 02 §1.1
  # rule 3). Refuses to run over a broken chain. Cached columns on contributions
  # are reset first so they too are rebuilt from the log.
  class Replay
    PROJECTIONS = Ledger::TableDigest::MODELS.map(&:constantize).freeze

    Result = Struct.new(:status, :applied, keyword_init: true)

    def self.call = new.call

    def call
      verification = Verify.call
      raise ChainBroken, "refusing to replay: #{verification.first_break.inspect}" unless verification.ok?

      applied = 0
      Ledger.applying do
        Contribution.transaction do
          Contribution.with_connection { |c| c.execute("TRUNCATE #{PROJECTIONS.map(&:table_name).join(', ')}") }
          Contribution.where(action_class: Contribution::CONTROL).update_all(current_status: Contribution::ACCEPTED)
          Contribution.where(action_class: Contribution::EPISTEMIC).update_all(current_status: Contribution::PENDING)
          last = -1
          loop do
            batch = Contribution.where("seq > ?", last).in_order.limit(500).to_a
            break if batch.empty?

            batch.each { |contribution| Apply.call(contribution); applied += 1 }
            last = batch.last.seq
          end
        end
      end

      Result.new(status: "REPLAYED", applied: applied)
    end
  end
end
