# A person's own view of a claim (spec 02 §3.6a, Article XV): agree or
# disagree, with an optional reason in their own words. Personal belief, kept
# outside the log; never evidence, never averaged into the shared assessment,
# never shown as Galedra's view. lens, personal_probability, and cites are the
# spec's reserved fields for a later personal scoring lens; empty for now.
class PersonalAssessment < ApplicationRecord
  STANCES = %w[AGREE DISAGREE].freeze
  VISIBILITIES = %w[PRIVATE PUBLIC].freeze
  MAX_RATIONALE = 500

  belongs_to :user
  belongs_to :claim

  validates :stance, inclusion: { in: STANCES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :rationale, length: { maximum: MAX_RATIONALE }, allow_nil: true

  def self.set!(user:, claim:, stance:, rationale: nil)
    record = find_or_initialize_by(user: user, claim: claim)
    record.id ||= SecureRandom.uuid_v7
    record.stance = stance
    changed = record.rationale != rationale.presence&.strip&.[](0, MAX_RATIONALE)
    record.rationale = rationale.presence&.strip&.[](0, MAX_RATIONALE)
    record.save!
    ContentReview.enqueue!(record) if changed
    record
  end
end
