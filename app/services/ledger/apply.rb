# frozen_string_literal: true

module Ledger
  # Projects one contribution onto the projection tables. A pure function of the
  # contribution and the current projections, so replay reproduces every row.
  module Apply
    def self.call(contribution)
      if contribution.redacted?
        Ledger.applying do
          Redaction.rebuild!(contribution)
          Audits::Sample.schedule!(contribution) if contribution.epistemic?
        end
        return
      end

      applier = Appliers.for(contribution.action_type)
      return if applier.nil?

      Ledger.applying do
        applier.apply(contribution)
        Audits::Sample.schedule!(contribution) if contribution.epistemic?
      end
    end
  end
end
