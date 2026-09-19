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

    # What the folded anonymous rows are shown as. It answers the few messages
    # the leaderboard and the API ask of a contributor; a nil id is what says
    # there is no page to link to, because there is no one key behind it.
    Anonymous = Data.define(:principals) do
      def id = nil
      def key_id = nil
      def display_name = "Anonymous"
      def identity_tier = "ANONYMOUS"
      def anonymous? = true
    end

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

    # [[contributor, counts]] most work first, the system key left out, and
    # every anonymous principal folded into one row (owner request, 2026-09-19).
    # Each anonymous connection mints its own key, so listing them separately
    # would be a page of identical "Anonymous" lines standing for nobody. The
    # work is still counted; it is simply not attributed to a person.
    def top(limit: 100, since: nil)
      all = counts(since: since)
      contributors = Contributor.where(id: all.keys).where.not(kind: Contributor::SYSTEM).index_by(&:id)
      named, anonymous = all.filter_map { |id, c| contributors[id] && [ contributors[id], c ] }
                            .partition { |contributor, _| !contributor.anonymous? }
      named << [ Anonymous.new(principals: anonymous.size), sum(anonymous.map(&:last)) ] if anonymous.any?
      named.sort_by { |row, c| [ -c[:total], row.id.to_s ] }.first(limit)
    end

    def sum(rows)
      totals = COLUMNS.to_h { |name| [ name.to_sym, rows.sum { |r| r.fetch(name.to_sym) } ] }
      totals.merge(total: totals.values.sum)
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
