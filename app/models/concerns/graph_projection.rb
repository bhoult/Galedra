# An evidence-graph projection row: read-only outside Ledger::Apply, windowed by
# seq, attributed to the contribution that created it.
module GraphProjection
  extend ActiveSupport::Concern
  include Projection
  include ValidityWindow

  included do
    belongs_to :contribution
  end
end
