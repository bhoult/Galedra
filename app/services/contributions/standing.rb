# frozen_string_literal: true

module Contributions
  # A contribution's standing as of a seq, derived from the ACCEPT and
  # INVALIDATE entries that name it.
  module Standing
    module_function

    def accepted_at?(contribution, seq)
      return false if contribution.seq > seq

      accepts = Contribution.where(action_type: "ACCEPT").where("seq <= ?", seq).where("payload->>'contribution_id' = ?", contribution.id).maximum(:seq)
      return false if accepts.nil?

      invalidations = Contribution.where(action_type: "INVALIDATE").where("seq <= ?", seq).where("payload->>'contribution_id' = ?", contribution.id).maximum(:seq)
      invalidations.nil? || invalidations < accepts
    end
  end
end
