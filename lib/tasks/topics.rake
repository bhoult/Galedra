namespace :topics do
  desc "File untagged claims under topics guessed from their wording (system-signed TAG_CLAIM entries)"
  task backfill: :environment do
    Topics::Backfill.call(out: $stdout, replace: ENV["REPLACE"] == "1")
  end
end
