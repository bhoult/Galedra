# frozen_string_literal: true

module Ledger
  # Projects one contribution onto the projection tables. A pure function of the
  # contribution and the current projections, so replay reproduces every row.
  module Apply
    def self.call(contribution)
      if contribution.redacted?
        Ledger.applying { Redaction.rebuild!(contribution) }
        return
      end

      applier = Appliers.for(contribution.action_type)
      return if applier.nil?

      Ledger.applying { applier.apply(contribution) }
    end
  end
end
