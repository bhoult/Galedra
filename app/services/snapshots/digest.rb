# frozen_string_literal: true

module Snapshots
  # claim_score_digest (spec 06 §2): sha256 over the sorted (claim_id, trace_hash)
  # pairs of every claim that existed and was not quarantined at the seq, under
  # the default model. Two installations with the same log return the same digest.
  module Digest
    module_function

    def call(seq, model: Scoring::Registry.default_model)
      pairs = claims_at(seq).order(:id).map { |claim| [ claim.id, Scoring::Score.call(claim, seq, model).trace_hash ] }
      Crypto::Hashing.json(pairs)
    end

    def claims_at(seq)
      Claim.where(arel_table_created_lteq(seq)).where.not(id: Quarantine.active_at(seq).where(target_type: "CLAIM").select(:target_id))
    end

    def arel_table_created_lteq(seq)
      Claim.arel_table[:created_seq].lteq(seq)
    end
  end
end
