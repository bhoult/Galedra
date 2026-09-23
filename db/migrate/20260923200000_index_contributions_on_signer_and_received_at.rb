# frozen_string_literal: true

# The hourly write cap counts a signer's writes in the last hour on every write
# (AssistantToken#writes_this_hour). With only signer_key_id indexed, Postgres
# reads every one of that signer's rows and filters on received_at: 137 ms for a
# signer with 128,000 entries on the bench corpus, repeated per append, and
# growing for exactly the busiest assistants (audit, 2026-09-23).
class IndexContributionsOnSignerAndReceivedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :contributions, [ :signer_key_id, :received_at ], algorithm: :concurrently,
                                                                name: "index_contributions_on_signer_key_id_and_received_at"
  end
end
