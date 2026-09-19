# frozen_string_literal: true

module Snapshots
  # Pins a (seq, entry_hash) with an optional label (spec 02 §3.5). Since
  # Stage 23 every pin also carries a checkpoint signed by the node.
  module Create
    module_function

    def call(seq:, label: nil)
      entry = Contribution.find_by(seq: seq)
      raise Ledger::Rejected.new([ { code: "SNAPSHOT_UNKNOWN", path: "$.seq", detail: "no log entry at seq #{seq}" } ]) if entry.nil?

      GraphSnapshot.find_by(seq: seq) || begin
        now = Time.current
        previous = GraphSnapshot.where("seq < ?", seq).order(seq: :desc).first
        checkpoint = Checkpoint.build(seq: seq, entry_hash: entry.entry_hash, previous_seq: previous&.seq, created_at: now)
        GraphSnapshot.create!(seq: seq, entry_hash: entry.entry_hash, label: label, created_at: now, checkpoint: checkpoint)
      end
    end
  end
end
