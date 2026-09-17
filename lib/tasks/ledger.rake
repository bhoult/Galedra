namespace :ledger do
  desc "Generate an Ed25519 system key pair; paste the output into .env"
  task keygen: :environment do
    pair = Crypto::Ed25519::KeyPair.generate
    puts "#{Crypto::SystemKey::PRIVATE_ENV}=#{pair.private_key}"
    puts "#{Crypto::SystemKey::PUBLIC_ENV}=#{pair.public_key}"
    puts "# key_id: #{pair.key_id}"
  end

  desc "Append seq 0 (the system key's self-signed REGISTER_KEY) if the log is empty"
  task genesis: :environment do
    contribution = Ledger::Genesis.ensure!
    puts "genesis seq #{contribution.seq} entry_hash #{contribution.entry_hash} key #{contribution.signer_key_id}"
  end

  desc "Recompute every hash and check every signature in the log"
  task verify: :environment do
    result = Ledger::Verify.call
    puts "#{result.status}: #{result.checked} entries, head seq #{result.head_seq.inspect}, head #{result.head_hash.inspect}"
    puts "redacted seqs: #{result.redacted_seqs.join(', ')}" if result.redacted_seqs.present?
    if result.first_break
      puts "first break at seq #{result.first_break[:seq]}: #{result.first_break[:reason]}"
      exit 1
    end
  end

  desc "Truncate every projection and rebuild it from the log"
  task replay: :environment do
    result = Ledger::Replay.call
    puts "#{result.status}: re-applied #{result.applied} contributions"
  end
end

# Owner-level database work must not run under the restricted role.
Rake::Task["db:load_config"].enhance { ENV[Ledger::DatabaseRole::PRIVILEGED_ENV] ||= "1" }

%w[db:prepare db:migrate db:schema:load db:setup db:reset db:test:prepare].each do |name|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance([ "environment" ]) { Ledger::DatabaseRole.ensure_all! }
end
