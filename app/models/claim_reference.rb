# How often a claim is referenced (owner request, 2026-09-19), so that the
# claims people keep meeting can be found: the most-checked claims whose
# evidence contradicts them are the common misconceptions. A count is not
# evidence and never reaches scoring; it is analytics outside the log, one
# row per claim, kind, and day, with no foreign key so that replay, which
# truncates and rebuilds claims, leaves the counts standing. Spec 06 §4 rule
# 12 still holds: lists are
# ordered by how often, never by how "wrong", and worded neutrally.
class ClaimReference < ApplicationRecord
  # CHECKED: in a recorded investigation (someone wanted it checked).
  # LOOKED_UP: read by an assistant (get_claim, fetch, explain).
  # VIEWED: the claim page was opened. SHARED: a share card or a check page
  # holding it was opened, which is what happens when a link is posted.
  KINDS = %w[CHECKED LOOKED_UP VIEWED SHARED].freeze

  belongs_to :claim

  validates :kind, inclusion: { in: KINDS }

  # Adds one to today's row for each claim. Never raises: a failed count must
  # not break the read or write it rides on.
  def self.count!(claim_ids, kind)
    ids = Array(claim_ids).compact.uniq
    return if ids.empty?
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)

    day = Time.current.utc.to_date
    rows = ids.map { |id| { id: SecureRandom.uuid_v7, claim_id: id, kind: kind, day: day, count: 1 } }
    upsert_all(rows, unique_by: [ :claim_id, :kind, :day ], on_duplicate: Arel.sql("count = claim_references.count + EXCLUDED.count"))
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("claim_reference count failed kind=#{kind} #{e.class}: #{e.message}")
    nil
  end

  # {"CHECKED" => n, ..., "total" => n} for one claim, optionally since a date.
  def self.totals(claim_id, since: nil)
    scope = where(claim_id: claim_id)
    scope = scope.where("day >= ?", since) if since
    counts = scope.group(:kind).sum(:count)
    KINDS.to_h { |k| [ k, counts.fetch(k, 0) ] }.merge("total" => counts.values.sum)
  end

  # {claim_id => count} over a set of claims, one kind or all, optionally since a date.
  def self.counts_for(claim_ids, kind: nil, since: nil)
    scope = where(claim_id: claim_ids)
    scope = scope.where(kind: kind) if kind
    scope = scope.where("day >= ?", since) if since
    scope.group(:claim_id).sum(:count)
  end

  # Claim ids ordered by references, most first: the substrate for "most checked".
  def self.top_claim_ids(kind: nil, since: nil, limit: 100)
    scope = all
    scope = scope.where(kind: kind) if kind
    scope = scope.where("day >= ?", since) if since
    scope.group(:claim_id).order(Arel.sql("SUM(count) DESC")).limit(limit).pluck(:claim_id)
  end

  def self.since_for(window)
    case window.to_s
    when "7d" then 7.days.ago.utc.to_date
    when "30d" then 30.days.ago.utc.to_date
    when "365d" then 365.days.ago.utc.to_date
    end
  end
end
