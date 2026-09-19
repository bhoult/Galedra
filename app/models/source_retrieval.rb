# One fetch of a source held by reference, by Galedra's own job (Stage 17,
# spec 04 §6 step 9). Projection of RETRIEVE_SOURCE; sits beside the reader's
# record and never changes it. Page text is not stored: only the hash, the
# size, the media type, the final address, and each excerpt's finding.
class SourceRetrieval < ApplicationRecord
  include GraphProjection

  OUTCOMES = %w[FETCHED NOT_FOUND BLOCKED TIMEOUT TOO_LARGE UNSUPPORTED REFUSED].freeze
  FINDINGS = %w[VERBATIM NORMALIZED NOT_FOUND UNSUPPORTED].freeze

  belongs_to :source

  validates :outcome, inclusion: { in: OUTCOMES }

  scope :latest_first, -> { order(created_seq: :desc) }

  def fetched? = outcome == "FETCHED"

  def finding_for(location_id)
    excerpts.find { |e| e["location_id"] == location_id }&.fetch("found", nil)
  end

  # The most recent retrieval of a source at a seq, if any.
  def self.latest_for(source_id, seq = nil)
    scope = where(source_id: source_id)
    scope = scope.active_at(seq) if seq
    scope.latest_first.first
  end
end
