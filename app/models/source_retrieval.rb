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
  #
  # INTERRUPTED (Stage 36) is a third fact where NOT_FOUND used to say two: the
  # passage is on the page, but inline markup sits inside it — a ticker chip, a
  # footnote marker — so it matches only once that one-token element is left
  # out, which is what a reader does. Bug report 33349d5d: qz.com wrote
  # "Nvidia<a>$NVDA</a>'s" and an accurate quotation was labelled missing.
  FINDINGS = %w[VERBATIM NORMALIZED INTERRUPTED NOT_FOUND NOT_READ UNSUPPORTED].freeze

  # Which reading of the page matched, when it was not the page as served.
  # Named rather than shown: page text is never stored (Stage 17).
  RENDERINGS = %w[INLINE_JOINED INLINE_ELIDED].freeze
  RENDERING_MEANS = {
    "INLINE_JOINED" => "it matched once the spaces this server inserts at inline tags were taken out",
    "INLINE_ELIDED" => "it matched once a one-word inline element inside it, such as a ticker or a footnote marker, was left out"
  }.freeze

  # What each finding means to somebody reading it, in one sentence, so the word
  # is never the only thing carrying the meaning.
  FINDING_MEANS = {
    "VERBATIM" => "the passage is on the page, character for character",
    "NORMALIZED" => "the passage is on the page once typography is folded together",
    "INTERRUPTED" => "the passage is on the page, with inline markup such as a ticker or a footnote marker inside it",
    "NOT_FOUND" => "this server looked at the page and did not find the passage",
    "NOT_READ" => "this server does not read this kind of document or recording, so it has not looked; read it yourself",
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

  def rendering_for(location_id)
    excerpts.find { |e| e["location_id"] == location_id }&.fetch("rendering", nil)
  end

  def self.rendering_means(rendering) = RENDERING_MEANS[rendering.to_s]

  # The most recent retrieval of a source at a seq, if any.
  def self.latest_for(source_id, seq = nil)
    scope = where(source_id: source_id)
    scope = scope.active_at(seq) if seq
    scope.latest_first.first
  end
end
