# One recorded check (after Stage 19): the statement a person wanted checked,
# as they would post it, and the claims that answer it. The page at
# /investigations/:id is the link to paste. Claims and cards come from the log.
class Investigation < ApplicationRecord
  MAX_STATEMENT_CHARS = 2_000

  belongs_to :assistant_token

  validates :statement, length: { maximum: MAX_STATEMENT_CHARS }, allow_nil: true
  validates :claim_ids, presence: true, unless: :section_id

  def outline? = section_id.present?

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

  # The one line to paste: a headline, the counts behind it for a whole
  # statement, the number in its stated form when there is one, and the link.
  def self.share_line(headline:, url:, detail: nil, stated: nil)
    "Checked in Galedra: #{headline}#{" (#{detail})" if detail.present?}#{" #{stated}." if stated} #{url}"
  end

  # The verdict for a whole check, or the single claim's card when one claim answers.
  def self.summary(cards, verdict)
    if cards.size == 1
      { headline: cards.first[:plain][:headline], detail: nil, stated: cards.first[:stated], badge: verdict[:badge] }
    else
      { headline: verdict[:headline], detail: verdict[:sentence], stated: verdict[:stated], badge: verdict[:badge] }
    end
  end
end
