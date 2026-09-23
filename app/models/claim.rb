# One minimal proposition (spec 02 §3.3, claim types in 01 §4). There is
# deliberately no uniqueness on canonical_text. status, superseded_by_id,
# merged_into_id, truth_evaluable and not_evaluable_reason are the current
# view, recomputed by Projections::Refresh from windowed rows; history is
# answered by *_at(seq).
class Claim < ApplicationRecord
  include GraphProjection

  TYPES = %w[OBSERVATIONAL QUANTITATIVE HISTORICAL TEXTUAL COMPARATIVE CAUSAL FORECAST LEGAL
             INTERPRETIVE DEFINITIONAL ATTRIBUTED_BELIEF NORMATIVE RHETORICAL METAPHYSICAL].freeze
  DEFAULT_NOT_EVALUABLE = {
    "NORMATIVE" => "NORMATIVE_OR_VALUE", "RHETORICAL" => "RHETORICAL", "METAPHYSICAL" => "METAPHYSICAL",
    "FORECAST" => "UNRESOLVED_FORECAST", "LEGAL" => "NO_LEGAL_MODEL"
  }.freeze
  NOT_EVALUABLE_REASONS = %w[NORMATIVE_OR_VALUE METAPHYSICAL RHETORICAL UNTESTABLE_CURRENT_METHODS UNRESOLVED_FORECAST NO_LEGAL_MODEL].freeze
  STATUSES = %w[ACTIVE SUPERSEDED MERGED RETIRED QUARANTINED].freeze
  MAX_TEXT_CHARS = 2_000

  belongs_to :supersedes_claim, class_name: "Claim", optional: true
  has_many :evidence_claim_links, dependent: nil
  has_many :outgoing_edges, class_name: "ClaimEdge", foreign_key: :from_claim_id, inverse_of: :from_claim, dependent: nil
  has_many :incoming_edges, class_name: "ClaimEdge", foreign_key: :to_claim_id, inverse_of: :to_claim, dependent: nil

  # The same counted edges are asked for more than once while one claim renders:
  # the presenter's edges block and the card's related list issue byte-identical
  # queries (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md, finding 5).
  # Memoised per object and per seq — a Claim instance belongs to one request,
  # and the answer is a function of the log up to a seq, so it cannot go stale
  # inside that. The far side is preloaded because every caller reads it.
  def counted_outgoing_edges(seq)
    (@counted_outgoing_edges ||= {})[seq] ||= outgoing_edges.counted_at(seq).includes(:to_claim).to_a
  end

  def counted_incoming_edges(seq)
    (@counted_incoming_edges ||= {})[seq] ||= incoming_edges.counted_at(seq).includes(:from_claim).to_a
  end

  # For a caller that loaded a page of claims' edges at once
  # (Graph::Presenter.claims): the same rows the two methods above would load.
  def prime_counted_edges(seq, outgoing:, incoming:)
    (@counted_outgoing_edges ||= {})[seq] = outgoing
    (@counted_incoming_edges ||= {})[seq] = incoming
  end
  has_many :merges_from, class_name: "ClaimMerge", foreign_key: :from_claim_id, inverse_of: :from_claim, dependent: nil
  has_many :merges_into, class_name: "ClaimMerge", foreign_key: :into_claim_id, inverse_of: :into_claim, dependent: nil
  has_many :evaluability_settings, class_name: "ClaimEvaluabilitySetting", dependent: nil

  validates :canonical_text, presence: true, length: { maximum: MAX_TEXT_CHARS }, unless: :redacted?
  validates :claim_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :not_evaluable_reason, inclusion: { in: NOT_EVALUABLE_REASONS }, if: -> { !truth_evaluable }
  validates :not_evaluable_reason, absence: true, if: -> { truth_evaluable }

  def self.default_truth_evaluable(claim_type) = !DEFAULT_NOT_EVALUABLE.key?(claim_type)

  def redacted? = redacted_by_seq.present?

  def status_at(seq)
    return nil unless created_seq <= seq
    return "QUARANTINED" if Governance::Quarantines.quarantined_at?("CLAIM", id, seq)
    return "MERGED" if merge_at(seq)
    return "SUPERSEDED" if superseded_by_at(seq)
    return "RETIRED" unless active_at?(seq)

    "ACTIVE"
  end

  # The claim that supersedes this one as of S, if any.
  def superseded_by_at(seq)
    Claim.counted_at(seq).find_by(supersedes_claim_id: id)
  end

  def merge_at(seq)
    merges_from.counted_at(seq).first
  end

  # Current (windowed) claims can receive links and edges.
  def current_at?(seq)
    counted_at?(seq) && superseded_by_at(seq).nil? && merge_at(seq).nil?
  end

  def evaluability_at(seq)
    setting = evaluability_settings.counted_at(seq).order(accepted_seq: :desc).first
    if setting
      [ setting.truth_evaluable, setting.not_evaluable_reason ]
    else
      [ original_truth_evaluable, original_not_evaluable_reason ]
    end
  end

  # After a TAKEDOWN the payload is gone; the retained column values stand in.
  # The payload may be passed in by a caller that loaded it for a whole set
  # (Scoring::BuildInputBatch), which spares loading the whole ~1.9 KB row to
  # read two keys of it.
  def original_truth_evaluable(payload = contribution.payload)
    return truth_evaluable if payload.nil?

    payload.key?("truth_evaluable") ? payload["truth_evaluable"] : Claim.default_truth_evaluable(claim_type)
  end

  def original_not_evaluable_reason(payload = contribution.payload)
    return nil if original_truth_evaluable(payload)
    return not_evaluable_reason if payload.nil?

    payload["not_evaluable_reason"] || DEFAULT_NOT_EVALUABLE[claim_type]
  end
end
