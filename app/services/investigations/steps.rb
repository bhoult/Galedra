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

    # known_kinds maps an excerpt handle the bundle does not declare to its
    # kind: a task answer cites the packet's own passage as "packet"
    # (Tasks::Answer), and its kind is in the packet, not in the answer.
    def for_link(link, bundle, known_kinds: {})
      steps = link.fetch("steps", 0).to_i
      excerpt_handle = bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
      kind = bundle.fetch("excerpts", []).find { |e| e["handle"] == excerpt_handle }&.fetch("kind", "QUOTE")
      kind ||= known_kinds[excerpt_handle]
      kind == "TRANSCRIPTION" ? [ steps, 1 ].max : steps
    end
  end
end
