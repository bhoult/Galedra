# A table derived from the contribution log. Rows are written only while
# Ledger::Apply is running (spec 02 §1.1 rule 2); everything else sees them as
# read-only. Stage 3 adds validity-window scopes.
module Projection
  extend ActiveSupport::Concern

  def readonly?
    !Ledger.applying? || super
  end
end
