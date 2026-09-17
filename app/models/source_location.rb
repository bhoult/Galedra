# An exact place inside a source (spec 02 §3.2).
class SourceLocation < ApplicationRecord
  include GraphProjection

  LOCATOR_TYPES = %w[CHAR_RANGE PAGE SECTION LINE_RANGE TIME_RANGE OTHER].freeze

  belongs_to :source
  has_many :evidence_items, dependent: nil

  validates :locator_type, inclusion: { in: LOCATOR_TYPES }
end
