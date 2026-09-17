# An attributable assertion that an evidence item bears on a claim (spec 02
# §3.3). A link is counted at S when active, accepted, and not superseded by a
# counted link at S. note is display-only: never scored, never in packets.
class EvidenceClaimLink < ApplicationRecord
  include GraphProjection

  DIRECTIONS = %w[SUPPORT CONTRADICT QUALIFY NEUTRAL].freeze
  STRENGTHS = %w[DIRECT STRONG MODERATE WEAK CONTEXT_ONLY].freeze
  MAX_STEPS = 5

  belongs_to :evidence_item
  belongs_to :claim
  belongs_to :supersedes_link, class_name: "EvidenceClaimLink", optional: true

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :relevance_strength, inclusion: { in: STRENGTHS }
  validates :interpretive_steps, inclusion: { in: 0..MAX_STEPS }

  scope :not_superseded_at, ->(seq) {
    superseding = EvidenceClaimLink.counted_at(seq).where.not(supersedes_link_id: nil).select(:supersedes_link_id)
    where.not(id: superseding)
  }
  scope :effective_at, ->(seq) { counted_at(seq).not_superseded_at(seq) }

  def superseded_by_at(seq)
    EvidenceClaimLink.counted_at(seq).find_by(supersedes_link_id: id)
  end

  def effective_at?(seq)
    counted_at?(seq) && superseded_by_at(seq).nil?
  end
end
