# frozen_string_literal: true

namespace :assistants do
  desc "Bring every adopted assistant up to the named write and lease caps (idempotent; appends a DELEGATE only where the lease limit rises)"
  task named_caps: :environment do
    AssistantToken.where.not(user_id: nil).where(revoked_at: nil).find_each do |token|
      before = [ token.hourly_cap, token.delegation.max_tasks_per_hour ]
      Assistants::Connect.raise_to_named_caps!(token)
      after = [ token.hourly_cap, token.delegation.max_tasks_per_hour ]
      puts "#{token.id} writes/leases an hour #{before.join('/')} -> #{after.join('/')}" unless before == after
    rescue Ledger::Rejected => e
      puts "#{token.id} not raised: #{e.errors.map { |x| x[:detail] || x['detail'] }.join('; ')}"
    end
  end
end
