# A moderator's restriction on a claim or source (spec 05 §13). Control
# contribution, so it takes effect at its seq; RELEASE_QUARANTINE closes it.
# Quarantined text is withheld from public reads while the row is live, but a
# public stub, the moderator key, the reason, and the appeal path remain.
class Quarantine < ApplicationRecord
  include Projection

  TARGET_TYPES = %w[CLAIM SOURCE].freeze
  REASONS = %w[PRIVATE_INDIVIDUAL PERSONAL_DATA UNLAWFUL_CONTENT UNLICENSED_MATERIAL SPAM].freeze

  belongs_to :contribution

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :reason, inclusion: { in: REASONS }

  scope :live, -> { where(released_seq: nil) }
  scope :active_at, ->(seq) { where(arel_table[:created_seq].lteq(seq)).where(arel_table[:released_seq].eq(nil).or(arel_table[:released_seq].gt(seq))) }

  def released? = released_seq.present?

  def target
    target_type == "CLAIM" ? Claim.find_by(id: target_id) : Source.find_by(id: target_id)
  end
end
