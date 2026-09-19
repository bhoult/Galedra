# A node of an outline (Stage 20): a heading over one source, nested like a
# directory, with claims placed in it. A root section has no parent; every
# section in a tree shares the root's source. Projection of CREATE_SECTION.
class Section < ApplicationRecord
  include GraphProjection

  MAX_DEPTH = 6
  MAX_PER_CONTRIBUTION = 500
  MAX_PER_ROOT = 2_000
  MAX_HEADING = 120

  belongs_to :source
  belongs_to :parent, class_name: "Section", optional: true, inverse_of: :children
  belongs_to :location, class_name: "SourceLocation", optional: true
  # Stage 30. The anchor above is quoted exactly and checked against the source;
  # this is the section's text as an assistant read it, cleaned into paragraphs.
  # Readable, but not a quotation, and nothing verifies it.
  belongs_to :reading_location, class_name: "SourceLocation", optional: true
  has_many :children, class_name: "Section", foreign_key: :parent_id, inverse_of: :parent, dependent: nil
  has_many :placements, class_name: "ClaimPlacement", dependent: nil

  validates :heading, presence: true, length: { maximum: MAX_HEADING }, unless: :redacted?

  def redacted? = redacted_by_seq.present?
  def root? = parent_id.nil?
  def root = root? ? self : Section.find(root_id)

  # Root first.
  def ancestors(seq = nil)
    out = []
    node = self
    while node.parent_id
      node = Section.find(node.parent_id)
      break if seq && !node.counted_at?(seq)
      out.unshift(node)
    end
    out
  end

  def path(seq = nil) = ancestors(seq).map(&:heading) + [ heading ]
end
