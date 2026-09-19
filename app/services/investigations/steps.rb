# frozen_string_literal: true

module Investigations
  # A transcription is a reading, not a quotation: at least one interpretive
  # step. The rule belongs to the bundle vocabulary, so both write paths that
  # speak it read it here: record_investigation (Investigations::Record) and
  # submit_task (Tasks::Answer, whose answers use the same handles).
  # interpretive_steps feeds the per-step penalty in scoring and is frozen into
  # a signed contribution, so the two paths must weigh one passage alike.
  module Steps
    module_function

    def for_link(link, bundle)
      steps = link.fetch("steps", 0).to_i
      excerpt_handle = bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
      kind = bundle.fetch("excerpts", []).find { |e| e["handle"] == excerpt_handle }&.fetch("kind", "QUOTE")
      kind == "TRANSCRIPTION" ? [ steps, 1 ].max : steps
    end
  end
end
