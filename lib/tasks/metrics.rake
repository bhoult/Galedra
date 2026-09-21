# frozen_string_literal: true

namespace :metrics do
  desc "What the node is asked for and what it costs: bin/rails metrics:report (DAYS=7, LIMIT=20)"
  task report: :environment do
    days = Integer(ENV.fetch("DAYS", 7))
    limit = Integer(ENV.fetch("LIMIT", 20))
    since = days.days.ago
    tallies = RequestTally.since(since).group(:action)
                          .pluck(:action, Arel.sql("SUM(calls)"), Arel.sql("SUM(total_ms)"),
                                 Arel.sql("MAX(max_ms)"), Arel.sql("SUM(statements)"), Arel.sql("SUM(slow_calls)"))
    if tallies.empty?
      puts RequestMetrics.enabled? ? "nothing recorded in the last #{days} days" : "recording is off (#{RequestMetrics::ENV_KEY})"
      next
    end

    rows = tallies.map do |action, calls, total, max, statements, slow|
      { action: action, calls: calls.to_i, total: total.to_f, mean: total.to_f / calls.to_i,
        max: max.to_f, per_call: statements.to_i / [ calls.to_i, 1 ].max, slow: slow.to_i }
    end

    # By total time, because that is what optimising actually buys back: a slow
    # page nobody opens is not the problem a quick page opened constantly is.
    puts "\nWhere the time goes (last #{days} days)"
    printf("%-34s %8s %10s %9s %9s %7s %6s\n", "action", "calls", "total s", "mean ms", "max ms", "stmts", "slow")
    rows.sort_by { |r| -r[:total] }.first(limit).each do |r|
      printf("%-34s %8d %10.1f %9.1f %9.1f %7d %6d\n",
             r[:action], r[:calls], r[:total] / 1000, r[:mean], r[:max], r[:per_call], r[:slow])
    end

    puts "\nMost asked for"
    rows.sort_by { |r| -r[:calls] }.first(limit).each do |r|
      printf("%-34s %8d %10.1f %9.1f\n", r[:action], r[:calls], r[:total] / 1000, r[:mean])
    end

    samples = RequestSample.where(recorded_at: since..).slowest.limit(limit)
    puts "\nSlowest requests kept (over #{RequestMetrics::SLOW_MS} ms or #{RequestMetrics::MANY_STATEMENTS} statements)"
    printf("%-34s %9s %8s %9s %10s  %s\n", "action", "ms", "stmts", "db ms", "head seq", "when")
    samples.each do |s|
      printf("%-34s %9.1f %8d %9s %10s  %s\n", s.action, s.duration_ms, s.statements,
             s.db_ms&.round(1) || "-", s.head_seq || "-", s.recorded_at.utc.strftime("%Y-%m-%d %H:%M"))
    end
    puts ""
  end

  desc "Drop metrics older than KEEP_DAYS (default 30): bin/rails metrics:prune"
  task prune: :environment do
    result = RequestMetrics::Prune.call(keep_days: Integer(ENV.fetch("KEEP_DAYS", RequestMetrics::Prune::DEFAULT_KEEP_DAYS)))
    puts "deleted #{result[:tallies]} tallies and #{result[:samples]} samples older than #{result[:keep_days]} days"
  end

  desc "Drop everything recorded for one action, once it has been fixed: bin/rails 'metrics:clear[claims#show]'"
  task :clear, [ :action ] => :environment do |_, args|
    action = args[:action].to_s
    abort "name an action, e.g. bin/rails 'metrics:clear[claims#show]'" if action.empty?

    result = RequestMetrics::Prune.clear(action)
    puts "deleted #{result[:tallies]} tallies and #{result[:samples]} samples for #{action}"
    puts "the record of a problem that no longer exists would only make the next report lie about where the time goes"
  end
end
