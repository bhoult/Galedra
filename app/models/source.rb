# A stored artifact (spec 02 §3.2). P0 sources carry their text inside the
# CREATE_SOURCE payload, so the log is self-contained and replay rebuilds them.
class Source < ApplicationRecord
  include GraphProjection

  TYPES = %w[PRIMARY_TEXT SECONDARY_TEXT DATASET MEASUREMENT VIDEO AUDIO WEBSITE LEGAL_DOCUMENT TESTIMONY ARTIFACT OTHER].freeze
  PRIMARY_TYPES = %w[PRIMARY_TEXT DATASET MEASUREMENT LEGAL_DOCUMENT].freeze
  MAX_CONTENT_CHARS = 1_000_000

  has_many :source_locations, dependent: nil

  validates :source_type, inclusion: { in: TYPES }
  validates :title, presence: true
  validates :content_hash, presence: true, if: -> { content.present? }

  def content_length
    content&.length || 0
  end

  # Character offsets, not bytes (Unicode code points).
  def slice(start, finish)
    content&.[](start...finish)
  end
end
