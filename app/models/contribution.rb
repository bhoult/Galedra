# One signed entry in the append-only log (spec 02 §3.1). Rows are never
# updated except for the cached, replay-rebuildable current_status column, and
# never destroyed; the database role enforces the same rule (Ledger::DatabaseRole).
class Contribution < ApplicationRecord
  CONTROL = "CONTROL"
  EPISTEMIC = "EPISTEMIC"
  ACTION_CLASSES = [ CONTROL, EPISTEMIC ].freeze

  PENDING = "PENDING"
  ACCEPTED = "ACCEPTED"
  CHALLENGED = "CHALLENGED"
  INVALIDATED = "INVALIDATED"
  SUPERSEDED = "SUPERSEDED"
  STATUSES = [ PENDING, ACCEPTED, CHALLENGED, INVALIDATED, SUPERSEDED ].freeze

  CACHED_COLUMNS = %w[current_status].freeze
  GENESIS_PREV_HASH = ("0" * 64).freeze

  belongs_to :contributor, optional: true

  validates :seq, presence: true
  validates :action_class, inclusion: { in: ACTION_CLASSES }
  validates :action_type, inclusion: { in: Ledger::ActionTypes::ALL }
  validates :custody, inclusion: { in: Crypto::Custody::ALL }
  validates :current_status, inclusion: { in: STATUSES }

  before_update :allow_only_cached_columns
  before_destroy { raise Ledger::AppendOnlyViolation, "contributions are never deleted" }

  scope :in_order, -> { order(:seq) }

  def control? = action_class == CONTROL
  def epistemic? = action_class == EPISTEMIC
  def genesis? = seq.zero?
  def redacted? = redacted_by_seq.present?

  def received_at_rfc3339
    Ledger::Entry.timestamp(received_at)
  end

  # The accountable identity: a human is its own principal, an agent's
  # principal is the delegation it acted under, the system is itself.
  def principal_contributor
    return nil if contributor.nil?
    return contributor unless contributor.agent?

    AgentDelegation.find_by(id: envelope&.dig("delegation_id"))&.principal
  end

  def principal_contributor_id = principal_contributor&.id

  PROJECTION_MODELS = %w[Source SourceLocation Claim ClaimEdge IndependenceGroup IndependenceGroupAssignment
                         EvidenceItem EvidenceClaimLink ClaimMerge ClaimEvaluabilitySetting].freeze

  # Every projection row this contribution created.
  def projection_rows
    PROJECTION_MODELS.flat_map { |name| name.constantize.where(contribution_id: id).to_a }
  end

  private

  def allow_only_cached_columns
    illegal = changes.keys - CACHED_COLUMNS
    return if illegal.empty?

    raise Ledger::AppendOnlyViolation, "contribution #{seq}: #{illegal.join(', ')} cannot change after append"
  end
end
