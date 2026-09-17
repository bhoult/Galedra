# Validity windows on projection rows (spec 02 §1.3). A row is active at
# snapshot S iff created_seq <= S and (invalidated_seq is null or > S). Rows
# with accepted_seq are counted at S iff also accepted_seq <= S.
module ValidityWindow
  extend ActiveSupport::Concern

  included do
    scope :active_at, ->(seq) {
      where(arel_table[:created_seq].lteq(seq))
        .where(arel_table[:invalidated_seq].eq(nil).or(arel_table[:invalidated_seq].gt(seq)))
    }
    scope :accepted_at, ->(seq) { where(arel_table[:accepted_seq].not_eq(nil).and(arel_table[:accepted_seq].lteq(seq))) }
    scope :counted_at, ->(seq) { active_at(seq).accepted_at(seq) }
    scope :pending_at, ->(seq) { active_at(seq).where(arel_table[:accepted_seq].eq(nil).or(arel_table[:accepted_seq].gt(seq))) }
    scope :live, -> { where(invalidated_seq: nil) }
    scope :accepted, -> { where.not(accepted_seq: nil) }
  end

  def active_at?(seq)
    created_seq <= seq && (invalidated_seq.nil? || invalidated_seq > seq)
  end

  def accepted_at?(seq)
    respond_to?(:accepted_seq) && !accepted_seq.nil? && accepted_seq <= seq
  end

  def counted_at?(seq)
    active_at?(seq) && accepted_at?(seq)
  end

  def accepted?
    !respond_to?(:accepted_seq) || !accepted_seq.nil?
  end

  def invalidated?
    !invalidated_seq.nil?
  end
end
