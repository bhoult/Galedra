# frozen_string_literal: true

namespace :sources do
  desc "Fetch a source held by reference now and record what was found: bin/rails sources:retrieve[SOURCE_ID]"
  task :retrieve, [ :id ] => :environment do |_, args|
    source = Source.find(args[:id].to_s)
    contribution = Sources::Retrieve.call(source, force: true)
    abort "#{source.id} carries stored content or has no link; nothing to fetch" if contribution.nil?
    row = SourceRetrieval.find(Ledger::Ids.derive(contribution.id, "retrieval"))
    puts "seq #{contribution.seq}: #{row.outcome}#{" #{row.content_hash} (#{row.content_length} bytes, #{row.media_type})" if row.fetched?}"
    row.excerpts.each { |e| puts "  #{e['location_id']}: #{e['found']}" }
  end
end
