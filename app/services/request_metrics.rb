# frozen_string_literal: true

# Stage 40: how long the node took, and how often it was asked.
#
# The Rails log records a duration and not a statement count, so the three slow
# paths found on 2026-09-21 — an outline page at 5,343 statements, a report
# building 3,500 entries to show fifty, a 2 KB trace read 200,000 times for nine
# fields — were all invisible in it. Counting statements is what found them, and
# it is what this records.
#
# Two tables, because there are two questions. `request_tallies` counts **every**
# request, one upsert per (action, hour), so the node can say what it is actually
# asked for: a page that takes two seconds once a day is not the problem a
# 300 ms page asked for constantly is. `request_samples` holds the individual
# slow ones, with the head seq beside them, because a timing without the corpus
# it was taken against is not evidence.
#
# Nothing here identifies anybody. No client address — Galedra records none, and
# a performance table is not a reason to start — and no user or contributor id.
# The request id is the one the Rails log already tags, so a row can be matched
# to a log line and to nothing else.
module RequestMetrics
  ENV_KEY = "LEDGER_REQUEST_METRICS"
  # A request is worth keeping in full if it was slow, or if it asked the
  # database an unreasonable number of times. The second is the one that finds
  # defects: an N+1 on a small corpus is fast and still wrong.
  SLOW_MS = 500
  MANY_STATEMENTS = 200
  COUNTER = :galedra_request_statements

  module_function

  # Off unless asked for, and read once per request rather than cached, so the
  # flag can be flipped in a console without a restart.
  def enabled?
    value = ENV.fetch(ENV_KEY, "off").to_s.downcase
    %w[1 true on yes].include?(value)
  end

  def start_request
    Thread.current[COUNTER] = 0
  end

  def count_statement
    count = Thread.current[COUNTER]
    Thread.current[COUNTER] = count + 1 unless count.nil?
  end

  def statements = Thread.current[COUNTER]

  def slow?(duration_ms, statements) = duration_ms >= SLOW_MS || statements.to_i >= MANY_STATEMENTS

  # Called after the response has been written. Anything raised here is swallowed
  # and logged: a broken metric must never break a page.
  def record(action:, method:, status:, duration_ms:, db_ms: nil, view_ms: nil, request_id: nil)
    return unless enabled?

    statements = self.statements.to_i
    Thread.current[COUNTER] = nil
    tally!(action, duration_ms, statements)
    sample!(action, method, status, duration_ms, db_ms, view_ms, statements, request_id) if slow?(duration_ms, statements)
  rescue StandardError => e
    Rails.logger.warn("request metrics: #{e.class}: #{e.message}")
  end

  # One statement, and it is the whole cost on the fast path. GREATEST rather
  # than a read-then-write, so two workers recording the same hour cannot lose
  # each other's counts.
  def tally!(action, duration_ms, statements)
    hour = Time.current.utc.beginning_of_hour
    now = Time.current
    RequestTally.upsert(
      { id: SecureRandom.uuid_v7, action: action, hour: hour, calls: 1, statements: statements,
        slow_calls: slow?(duration_ms, statements) ? 1 : 0, total_ms: duration_ms.round(2),
        max_ms: duration_ms.round(2), created_at: now, updated_at: now },
      unique_by: [ :action, :hour ],
      on_duplicate: Arel.sql(<<~SQL.squish)
        calls = request_tallies.calls + 1,
        statements = request_tallies.statements + EXCLUDED.statements,
        slow_calls = request_tallies.slow_calls + EXCLUDED.slow_calls,
        total_ms = request_tallies.total_ms + EXCLUDED.total_ms,
        max_ms = GREATEST(request_tallies.max_ms, EXCLUDED.max_ms),
        updated_at = EXCLUDED.updated_at
      SQL
    )
  end

  def sample!(action, method, status, duration_ms, db_ms, view_ms, statements, request_id)
    RequestSample.create!(
      id: SecureRandom.uuid_v7, action: action, method: method, status: status,
      duration_ms: duration_ms.round(2), db_ms: db_ms&.round(2), view_ms: view_ms&.round(2),
      statements: statements, head_seq: Contribution.maximum(:seq), request_id: request_id,
      recorded_at: Time.current
    )
  end
end
