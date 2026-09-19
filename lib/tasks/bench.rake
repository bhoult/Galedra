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

  desc "List the workloads the profiling tasks accept"
  task workloads: :environment do
    Bench::Workloads.names.each { |n| puts n }
  end

  desc "Sampling profile of one workload: bin/rails 'bench:cpu[weaknesses]' (MODE=cpu, RUNS=20)"
  task :cpu, [ :workload ] => :environment do |_, args|
    Bench::Profile.cpu(args[:workload], iterations: Integer(ENV.fetch("RUNS", 20)), mode: ENV.fetch("MODE", "wall").to_sym)
  end

  desc "What one run of a workload allocates and retains: bin/rails 'bench:memory[weaknesses]'"
  task :memory, [ :workload ] => :environment do |_, args|
    Bench::Profile.memory(args[:workload])
  end

  desc "Whether the process grows as it serves: bin/rails 'bench:rss[claims/:id]' (RUNS=100)"
  task :rss, [ :workload ] => :environment do |_, args|
    Bench::Profile.rss(args[:workload], iterations: Integer(ENV.fetch("RUNS", 100)))
  end

  desc "Resident set after boot, having served nothing"
  task boot: :environment do
    Bench::Profile.boot
  end
end
