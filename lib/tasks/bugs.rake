# frozen_string_literal: true

namespace :bugs do
  desc "Summarise bug reports from assistants and people (last N days, default 30)"
  task report: :environment do
    days = ENV.fetch("DAYS", "30").to_i
    rows = BugReport.where("updated_at >= ?", days.days.ago).order(count: :desc, updated_at: :desc)
    puts "#{rows.size} distinct reports in the last #{days} days (#{rows.sum(:count)} filings)"
    rows.each do |r|
      puts "#{r.count.to_s.rjust(3)}  #{r.updated_at.utc.strftime('%Y-%m-%d')}  #{r.reporter.ljust(20)[0, 20]}  #{r.happened[0, 100]}"
      puts "      #{[ ("expected: #{r.expected[0, 80]}" if r.expected), ("url: #{r.url}" if r.url), ("tool: #{r.context_tool}" if r.context_tool), ("error: #{r.last_error}" if r.last_error) ].compact.join('  ')}" if r.expected || r.url || r.context_tool || r.last_error
    end
  end
end
