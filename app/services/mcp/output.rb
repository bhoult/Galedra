# frozen_string_literal: true

module Mcp
  # A tool result checked against the outputSchema the caller was handed.
  #
  # A client that reads output schemas validates structuredContent against them
  # and throws the whole result away when it does not match, so a field sent as
  # null under a schema saying "object" fails the call on the caller's side while
  # this node logs it as ok. On 2026-09-28 an assistant working the queue through
  # xAI's connector was refused next_affiliation_review three times that way —
  # `proposal` is null when the deduplicator had no guess — and each time the log
  # here said outcome=ok (bug reports 01a0e96a, 01a0e992, 01a0e99a). A watcher
  # reading this node's log could not have seen it.
  #
  # Mcp::Arguments checks what arrives, leniently, because it follows what the
  # tools have always read. This checks what leaves, strictly, because the reader
  # is the client's validator and not ours.
  module Output
    VALIDATORS = Concurrent::Map.new

    module_function

    # The first few mismatches as "pointer (keyword)"; empty when the result
    # conforms. `data` is the result as the caller receives it: parsed JSON.
    def errors(tool, data)
      schema = tool[:outputSchema]
      return [] if schema.nil? || !data.is_a?(Hash)

      validator(tool[:name], schema).validate(data).first(3).map { |e| "#{e['data_pointer'].presence || '/'} (#{e['type']})" }
    end

    def validator(name, schema)
      VALIDATORS.compute_if_absent(name) { JSONSchemer.schema(JSON.parse(schema.to_json)) }
    end
  end
end
