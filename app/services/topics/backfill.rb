# frozen_string_literal: true

module Topics
  # Files untagged claims under topics guessed from their wording, as
  # system-signed TAG_CLAIM contributions with a note saying so. Nothing is
  # edited in place: every backfilled tag is a log entry anyone can challenge
  # or replace. Claims with no matching cue are left untagged and reported.
  module Backfill
    NOTE = "Backfill: guessed from the claim's wording by Topics.guess; replace it if it is wrong."

    module_function

    # replace: true re-guesses claims whose only current tags are earlier
    # backfills (a new system tag replaces the old one); tags set by people
    # or assistants are never touched.
    def call(limit: 2, out: nil, replace: false)
      seq = Contribution.maximum(:seq) || 0
      tagged = []
      skipped = []
      system_key = Crypto::SystemKey.key_id
      Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(:created_seq).find_each do |claim|
        current = ClaimTopic.current_at(Contribution.maximum(:seq)).where(claim_id: claim.id).includes(:contribution)
        next if current.any? && !(replace && current.all? { |row| row.contribution.signer_key_id == system_key })
        next if current.any? && replace && Topics.guess(claim.canonical_text, limit: limit) == current.map(&:topic)

        topics = Topics.guess(claim.canonical_text, limit: limit)
        if topics.empty?
          skipped << claim
          next
        end
        envelope = Contributions::Envelope.build(action_type: "TAG_CLAIM", payload: { "claim_id" => claim.id, "topics" => topics, "note" => NOTE },
                                                key_pair: Crypto::SystemKey.key_pair)
        Ledger::Append.call(envelope, custody: Crypto::Custody::SYSTEM)
        tagged << [ claim, topics ]
        out&.puts("tagged #{claim.canonical_text[0, 70]} -> #{topics.join(', ')}")
      end
      out&.puts("#{tagged.size} claims tagged, #{skipped.size} left untagged (no cue matched)")
      skipped.each { |c| out&.puts("  untagged: #{c.canonical_text[0, 90]}") }
      { tagged: tagged, skipped: skipped }
    end
  end
end
