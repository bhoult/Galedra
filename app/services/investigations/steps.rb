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
      steps = whole_number!(link.fetch("steps", 0))
      excerpt_handle = bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
      kind = bundle.fetch("excerpts", []).find { |e| e["handle"] == excerpt_handle }&.fetch("kind", "QUOTE")
      kind ||= known_kinds[excerpt_handle]
      kind == "TRANSCRIPTION" ? [ steps, 1 ].max : steps
    end

    # A count, or a refusal naming the field. An array here used to reach `to_i`
    # and raise NoMethodError, which escaped as an HTML 500 to a client that
    # speaks JSON-RPC; the caller could only find the right shape by reading the
    # stack trace it had been handed (Muse, `01a0cab9`, 2026-09-22). A string of
    # digits is still accepted, because it always was and refusing it now would
    # break callers over a change nobody asked for.
    def whole_number!(value)
      return value if value.is_a?(Integer)
      return value.to_i if value.is_a?(String) || value.is_a?(Float) || value.nil?

      raise ArgumentError, "links[].steps must be a whole number of interpretive steps, not #{value.class.name.downcase}"
    end
  end
end
