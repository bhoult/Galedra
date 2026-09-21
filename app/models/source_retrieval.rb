# One fetch of a source held by reference, by Galedra's own job (Stage 17,
# spec 04 §6 step 9). Projection of RETRIEVE_SOURCE; sits beside the reader's
# record and never changes it. Page text is not stored: only the hash, the
# size, the media type, the final address, and each excerpt's finding.
class SourceRetrieval < ApplicationRecord
  include GraphProjection

  OUTCOMES = %w[FETCHED NOT_FOUND BLOCKED TIMEOUT TOO_LARGE UNSUPPORTED REFUSED].freeze
  # NOT_READ is not a verdict about the passage. It says this server did not
  # read the document at all, which is a different fact from looking and not
  # finding — and the old vocabulary had one word for both. An Ipsos PDF holding
  # the primary figures behind a claim reported UNSUPPORTED, and a reader could
  # not tell that from a passage genuinely absent (01a0c0ec).
  #
  # Galedra's fetch was never the reader. Tasks::Answer already calls it "a fact
  # for you to weigh, not a verdict", and a connected assistant can open the PDF
  # and quote it. So the fix is to say plainly what was not done, not to build a
  # second-rate reader beside the one already doing the work.
  FINDINGS = %w[VERBATIM NORMALIZED NOT_FOUND NOT_READ UNSUPPORTED].freeze

  # What each finding means to somebody reading it, in one sentence, so the word
  # is never the only thing carrying the meaning.
  FINDING_MEANS = {
    "VERBATIM" => "the passage is on the page, character for character",
    "NORMALIZED" => "the passage is on the page once typography is folded together",
    "NOT_FOUND" => "this server looked at the page and did not find the passage",
    "NOT_READ" => "this server does not read this kind of document, so it has not looked; read it yourself",
    "UNSUPPORTED" => "there was no excerpt to check"
  }.freeze

  def self.means(finding) = FINDING_MEANS.fetch(finding.to_s, finding.to_s.downcase.tr("_", " "))

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
