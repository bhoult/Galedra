# frozen_string_literal: true

namespace :bench do
  desc "Seed a corpus through the real write path: bin/rails 'bench:seed[10000]' (add RESET=1 in development)"
  task :seed, [ :claims ] => :environment do |_, args|
    Bench::Seed.call(claims: args[:claims] || 1_000, reset: ENV["RESET"] == "1", batch: Integer(ENV.fetch("BATCH", 250)))
  end

  desc "Time the pages and services that matter at the current corpus size"
  task report: :environment do
    Bench::Report.call
  end
end
