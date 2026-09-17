# frozen_string_literal: true

module Audits
  # Whether a contribution has been audited CONFIRMED as of a seq (spec 03 §2
  # `provisional`). Audits arrive in Stage 7; until then nothing is confirmed,
  # so every counted link is provisional.
  module Status
    def self.confirmed?(_contribution_id, _seq)
      false
    end
  end
end
