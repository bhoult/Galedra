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
                         EvidenceItem EvidenceClaimLink ClaimMerge ClaimEvaluabilitySetting ClaimTopic SourceRetrieval
                         Section ClaimPlacement Inference InferencePremise].freeze

  # Which projection tables each action type can write, so a question about
  # one contribution asks the one or two tables it can have rows in instead of
  # all sixteen (Stage 26). Every append asks it — the watermark works out
  # which claims the entry reached — and a 25-claim investigation made 306
  # appends and 3,700 of these statements.
  #
  # `nil` means "any table": a task result carries arbitrary ops, and a takedown
  # is rebuilt across the graph. An empty list means the type creates no
  # projection row at all. Every action type must appear here, and each
  # applier's creates must fall inside its entry; spec/models/contribution_spec.rb
  # holds both, so a new type or a new create fails the build instead of
  # hiding rows from replay, redaction and the watermark.
  PROJECTIONS_BY_ACTION = {
    "CREATE_SOURCE" => %w[Source], "CREATE_SOURCE_LOCATION" => %w[SourceLocation],
    "CREATE_CLAIM" => %w[Claim ClaimPlacement], "SUPERSEDE_CLAIM" => %w[Claim ClaimPlacement],
    "SET_TRUTH_EVALUABLE" => %w[ClaimEvaluabilitySetting], "CREATE_EVIDENCE" => %w[EvidenceItem],
    "LINK_EVIDENCE" => %w[EvidenceClaimLink], "SUPERSEDE_LINK" => %w[EvidenceClaimLink],
    "CREATE_CLAIM_EDGE" => %w[ClaimEdge], "CREATE_INDEPENDENCE_GROUP" => %w[IndependenceGroup],
    "ASSIGN_INDEPENDENCE_GROUP" => %w[IndependenceGroupAssignment], "MERGE_CLAIMS" => %w[ClaimMerge],
    "TAG_CLAIM" => %w[ClaimTopic], "CREATE_SECTION" => %w[Section], "PLACE_CLAIM" => %w[ClaimPlacement],
    "CREATE_INFERENCE" => %w[ClaimEdge Inference InferencePremise], "RETRIEVE_SOURCE" => %w[SourceRetrieval],
    "TASK_RESULT" => nil, "TAKEDOWN" => nil,
    "REGISTER_KEY" => [], "DELEGATE" => [], "REVOKE_KEY" => [], "REVOKE_DELEGATION" => [], "ADOPT_KEY" => [],
    "ACCEPT" => [], "INVALIDATE" => [], "AUDIT" => [], "QUARANTINE" => [], "RELEASE_QUARANTINE" => [],
    "RELEASE_SCORING_MODEL" => [], "AMEND_CONSTITUTION" => []
  }.freeze

  # Every projection row this contribution created.
  def projection_rows
    projection_tables.flat_map { |name| name.constantize.where(contribution_id: id).to_a }
  end

  # The tables to ask. A task result writes only through each op's own applier
  # (Ledger::Appliers::TaskResult.apply), so its tables are its ops' tables, and
  # a null result — no ops — has none. A payload taken down, an op of a type
  # that may write anywhere, or anything unrecognised asks every table.
  def projection_tables
    return PROJECTIONS_BY_ACTION.fetch(action_type, nil) || PROJECTION_MODELS unless action_type == "TASK_RESULT"

    ops = payload.is_a?(Hash) ? payload["ops"] : nil
    return PROJECTION_MODELS unless ops.is_a?(Array)

    tables = ops.map { |op| op.is_a?(Hash) ? PROJECTIONS_BY_ACTION.fetch(op["op"], nil) : nil }
    tables.any?(&:nil?) ? PROJECTION_MODELS : tables.flatten.uniq
  end

  # The same, asking every table: what the guard spec compares against.
  def projection_rows_everywhere
    PROJECTION_MODELS.flat_map { |name| name.constantize.where(contribution_id: id).to_a }
  end

  private

  def allow_only_cached_columns
    illegal = changes.keys - CACHED_COLUMNS
    return if illegal.empty?

    raise Ledger::AppendOnlyViolation, "contribution #{seq}: #{illegal.join(', ')} cannot change after append"
  end
end
