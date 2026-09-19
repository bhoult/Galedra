# frozen_string_literal: true

module Contributors
  # How much work a principal has put in (owner request, 2026-09-19): what it
  # recorded, the tasks it answered, the audits and acceptances it made, and
  # the reviews it judged, with agents' work credited to the principal that
  # delegated it. Counts of volume, never of reliability: reputation stays
  # audit-derived per task and domain (Article X), and neither is a scoring
  # input (Invariant 8). Spec 06 §5 wants no aggregate prestige on the
  # contributor page; the owner asked for a leaderboard, so the numbers are
  # shown with what they are and are not.
  module Tally
    COLUMNS = %w[recorded task_results audits acceptances reviews].freeze
    NOTE = "Counts of work done, not of reliability or authority. Reputation is audited per task and domain; neither is a scoring input."

    module_function

    # {principal_id => {recorded:, task_results:, audits:, acceptances:, reviews:, total:}}
    def counts(principal_ids: nil, since: nil)
      rows = log_counts(principal_ids: principal_ids, since: since)
      reviews = review_counts(principal_ids: principal_ids, since: since)
      (rows.keys | reviews.keys).to_h do |id|
        r = rows.fetch(id, {})
        row = { recorded: r.fetch("recorded", 0), task_results: r.fetch("task_results", 0), audits: r.fetch("audits", 0), acceptances: r.fetch("acceptances", 0), reviews: reviews.fetch(id, 0) }
        [ id, row.merge(total: row.values.sum) ]
      end
    end

    def for(principal_id, since: nil)
      counts(principal_ids: [ principal_id ], since: since).fetch(principal_id, { recorded: 0, task_results: 0, audits: 0, acceptances: 0, reviews: 0, total: 0 })
    end

    # [[contributor, counts]] most work first, the system key left out.
    def top(limit: 100, since: nil)
      all = counts(since: since)
      ids = all.sort_by { |id, c| [ -c[:total], id ] }.map(&:first)
      contributors = Contributor.where(id: ids).where.not(kind: Contributor::SYSTEM).index_by(&:id)
      ids.filter_map { |id| contributors[id] && [ contributors[id], all[id] ] }.first(limit)
    end

    def log_counts(principal_ids:, since:)
      conn = ActiveRecord::Base.connection
      where = [ "c.seq > 0", "c.contributor_id IS NOT NULL", "c.current_status <> 'INVALIDATED'" ]
      where << "c.received_at >= #{conn.quote(since)}" if since
      where << "COALESCE(d.principal_contributor_id, c.contributor_id) IN (#{principal_ids.map { |i| conn.quote(i) }.join(', ')})" if principal_ids
      conn.select_all(<<~SQL).to_h { |r| [ r["principal_id"], r ] }
        SELECT COALESCE(d.principal_contributor_id, c.contributor_id)::text AS principal_id,
               COUNT(*) FILTER (WHERE c.action_class = 'EPISTEMIC' AND c.action_type <> 'TASK_RESULT')::int AS recorded,
               COUNT(*) FILTER (WHERE c.action_type = 'TASK_RESULT')::int AS task_results,
               COUNT(*) FILTER (WHERE c.action_type = 'AUDIT')::int AS audits,
               COUNT(*) FILTER (WHERE c.action_type = 'ACCEPT')::int AS acceptances
        FROM contributions c
        LEFT JOIN agent_delegations d ON d.id::text = c.envelope->>'delegation_id'
        WHERE #{where.join(' AND ')}
        GROUP BY 1
      SQL
    end

    def review_counts(principal_ids:, since:)
      scope = ReviewVerdict.all
      scope = scope.where(principal_contributor_id: principal_ids) if principal_ids
      scope = scope.where("created_at >= ?", since) if since
      scope.group(:principal_contributor_id).count.transform_keys(&:to_s)
    end
  end
end
