# One principal's verdict on a review item (a content review by id, or an
# affiliation request by its normalized text). Reviews::Consensus reads them.
class ReviewVerdict < ApplicationRecord
  SUBJECTS = %w[ContentReview AffiliationRequest].freeze

  validates :subject_type, inclusion: { in: SUBJECTS }
  validates :verdict, presence: true

  # The identity of a verdict for counting agreement: the same action on the
  # same thing, whatever the wording of the reason.
  def key = [ verdict, detail.slice("slug").presence ].compact.join(":")
end
