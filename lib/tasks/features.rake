# frozen_string_literal: true

namespace :features do
  desc "Summarise what assistants said they could not do (last N days, default 30)"
  task report: :environment do
    days = ENV.fetch("DAYS", "30").to_i
    rows = FeatureRequest.where("updated_at >= ?", days.days.ago).order(count: :desc, updated_at: :desc)
    puts "#{rows.size} distinct needs in the last #{days} days (#{rows.sum(:count)} filings)"
    rows.each do |r|
      puts "#{r.count.to_s.rjust(3)}  #{r.updated_at.utc.strftime('%Y-%m-%d')}  #{r.anonymous ? 'anon ' : 'named'}  #{r.context_tool.to_s.ljust(20)}  #{r.needed[0, 100]}"
      puts "      asked: #{r.asked[0, 100]}#{"  expected: #{r.expected}" if r.expected}#{"  error: #{r.last_error}" if r.last_error}"
    end
  end
end
