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
  has_many :merges_from, class_name: "ClaimMerge", foreign_key: :from_claim_id, inverse_of: :from_claim, dependent: nil
  has_many :merges_into, class_name: "ClaimMerge", foreign_key: :into_claim_id, inverse_of: :into_claim, dependent: nil
  has_many :evaluability_settings, class_name: "ClaimEvaluabilitySetting", dependent: nil

  validates :canonical_text, presence: true, length: { maximum: MAX_TEXT_CHARS }
  validates :claim_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :not_evaluable_reason, inclusion: { in: NOT_EVALUABLE_REASONS }, if: -> { !truth_evaluable }
  validates :not_evaluable_reason, absence: true, if: -> { truth_evaluable }

  def self.default_truth_evaluable(claim_type) = !DEFAULT_NOT_EVALUABLE.key?(claim_type)

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

  def status_at(seq)
    return nil unless active_at?(seq) || (created_seq <= seq)
    return "MERGED" if merge_at(seq)
    return "SUPERSEDED" if superseded_by_at(seq)
    return "RETIRED" unless active_at?(seq)

    "ACTIVE"
  end

  def evaluability_at(seq)
    setting = evaluability_settings.counted_at(seq).order(accepted_seq: :desc).first
    if setting
      [ setting.truth_evaluable, setting.not_evaluable_reason ]
    else
      [ original_truth_evaluable, original_not_evaluable_reason ]
    end
  end

  def original_truth_evaluable
    contribution.payload.key?("truth_evaluable") ? contribution.payload["truth_evaluable"] : Claim.default_truth_evaluable(claim_type)
  end

  def original_not_evaluable_reason
    return nil if original_truth_evaluable

    contribution.payload["not_evaluable_reason"] || DEFAULT_NOT_EVALUABLE[claim_type]
  end
end
