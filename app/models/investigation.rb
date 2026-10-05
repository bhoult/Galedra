# One recorded check (after Stage 19): the statement a person wanted checked,
# as they would post it, and the claims that answer it. The page at
# /investigations/:id is the link to paste. Claims and cards come from the log.
class Investigation < ApplicationRecord
  # The text the person wanted checked, whole. The cap is Guidance::SIZE's limit
  # for one record_investigation call, about 3,000 words. It was 2,000
  # characters until 2026-10-05, so a paragraph the size rule said to record
  # whole had to be cut or summarised to fit (owner).
  MAX_STATEMENT_CHARS = 20_000
  # An outline's statement is its title and link, never its text.
  MAX_OUTLINE_STATEMENT_CHARS = 2_000

  belongs_to :assistant_token

  validates :statement, length: { maximum: MAX_STATEMENT_CHARS }, allow_nil: true
  validates :claim_ids, presence: true, unless: :section_id

  def outline? = section_id.present?

  # The checks a claim appeared in, newest first. Containment against the array
  # column, which the GIN index covers.
  scope :covering, ->(claim_id) { where("claim_ids @> ARRAY[?]::uuid[]", claim_id).order(created_at: :desc) }

  # What to show for a check in a list: the statement someone pasted, or the
  # single claim that answered it.
  def title(claims = nil)
    statement.presence || (claims || self.claims).first&.canonical_text
  end

  # Stage 21: an outline's investigation reads the claims under its root live.
  def claims
    if outline?
      seq = Contribution.maximum(:seq)
      root = Section.find_by(id: section_id)
      return [] if root.nil?

      ids = ClaimPlacement.counted_at(seq).where(section_id: Section.counted_at(seq).where(root_id: root.root_id).select(:id)).pluck(:claim_id)
      return Claim.counted_at(seq).where(id: ids).order(:created_seq).to_a
    end
    by_id = Claim.where(id: claim_ids).index_by(&:id)
    claim_ids.filter_map { |id| by_id[id] }
  end

  # What to paste (Cards::ShareText): the badge, the score when there is one,
  # the statement, and the link. While the check holds only an assistant's
  # first reading (Stage 45, Investigations::Preliminary.reading), that reading,
  # labelled as unsourced and an AI's, in place of a badge there is not yet.
  def self.share_line(summary, url:, quote:, reading: nil)
    return Cards::ShareText.preliminary(phrase: reading[:phrase], url: url, quote: quote) if reading&.dig(:preliminary)

    Cards::ShareText.call(label: summary[:label], figure: summary[:figure], quote: quote, url: url, reviewed: summary[:reviewed])
  end

  # The verdict for a whole check, or the single claim's card when one claim answers.
  def self.summary(cards, verdict)
    reviewed = cards.none? { |c| c[:provisional] }
    if cards.size == 1
      card = cards.first
      { headline: card[:plain][:headline], detail: nil, stated: card[:stated], badge: verdict[:badge], figure: card[:probability],
        label: Cards::Badge.for(card[:assessment_state], card[:probability])[:label], reviewed: reviewed }
    else
      { headline: verdict[:headline], detail: verdict[:sentence], stated: verdict[:stated], badge: verdict[:badge], figure: verdict[:figure],
        label: Cards::Badge.for_key(verdict[:badge])[:label], reviewed: reviewed }
    end
  end
end
