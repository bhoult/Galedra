# Pins a snapshot (spec 06 §2 POST /admin/snapshots).
class CreateSnapshotJob < ApplicationJob
  queue_as :default

  def perform(seq, label = nil)
    Snapshots::Create.call(seq: seq, label: label)
  end
end
