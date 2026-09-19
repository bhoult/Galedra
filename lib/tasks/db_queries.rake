# frozen_string_literal: true

namespace :db do
  desc "The statements costing the most, from pg_stat_statements: bin/rails db:top_queries (LIMIT=20, RESET=1 to zero it first)"
  task top_queries: :environment do
    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_stat_statements") rescue nil # rubocop:disable Style/RescueModifier
    if ENV["RESET"] == "1"
      conn.execute("SELECT pg_stat_statements_reset()")
      puts "counters reset; exercise the application, then run this again"
      next
    end

    rows = conn.select_all(<<~SQL)
      SELECT calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 2) AS mean_ms,
             rows, left(regexp_replace(query, '\\s+', ' ', 'g'), 150) AS query
      FROM pg_stat_statements
      WHERE query NOT LIKE '%pg_stat_statements%'
      ORDER BY total_exec_time DESC
      LIMIT #{Integer(ENV.fetch('LIMIT', 20))}
    SQL
    printf("%10s %12s %10s %10s  %s\n", "calls", "total ms", "mean ms", "rows", "query")
    rows.each { |r| printf("%10d %12s %10s %10d  %s\n", r["calls"], r["total_ms"], r["mean_ms"], r["rows"], r["query"]) }
  rescue ActiveRecord::StatementInvalid => e
    warn "pg_stat_statements is not available: #{e.message.lines.first}"
    warn "It needs shared_preload_libraries=pg_stat_statements and a database restart; docker compose sets that."
  end
end
