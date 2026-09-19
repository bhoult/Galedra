# Stage 17: fetches one source held by reference and records what it found.
# Keyed by (source_id, created_seq) and idempotent: a source already retrieved
# at that seq is left alone unless force is given (bin/rails sources:retrieve).
class RetrieveSourceJob < ApplicationJob
  queue_as :default

  def perform(source_id, created_seq, force: false)
    source = Source.find_by(id: source_id, created_seq: created_seq)
    return if source.nil? || !Sources::Retrieve.enabled?

    Sources::Retrieve.call(source, force: force)
  end
end
