# frozen_string_literal: true

module Snapshots
  # Pins a (seq, entry_hash) with an optional label (spec 02 §3.5).
  module Create
    module_function

    def call(seq:, label: nil)
      entry = Contribution.find_by(seq: seq)
      raise Ledger::Rejected.new([ { code: "SNAPSHOT_UNKNOWN", path: "$.seq", detail: "no log entry at seq #{seq}" } ]) if entry.nil?

      GraphSnapshot.find_by(seq: seq) || GraphSnapshot.create!(seq: seq, entry_hash: entry.entry_hash, label: label, created_at: Time.current)
    end
  end
end
