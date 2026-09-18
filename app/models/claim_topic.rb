# A topic on a claim (Stage 15): a judgment, recorded by TAG_CLAIM, windowed
# like every projection, and replaced when the same principal tags again.
class ClaimTopic < ApplicationRecord
  include GraphProjection

  belongs_to :claim

  validates :topic, inclusion: { in: ->(_) { Topics.all } }

  # Counted and not yet replaced by a later tag from the same principal.
  scope :current_at, ->(seq) { counted_at(seq).where(arel_table[:replaced_seq].eq(nil).or(arel_table[:replaced_seq].gt(seq))) }
end
