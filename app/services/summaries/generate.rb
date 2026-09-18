# frozen_string_literal: true

module Summaries
  # Builds, validates, caches, and serves summaries (spec 04 §10, 02 §3.5). A
  # summary is stale when the input hash changes; the cache row is then replaced.
  module Generate
    module_function

    def call(claim, seq, model, type: "STANDARD", adapter: Llm::Adapter.current)
      raise ArgumentError, "unknown summary type #{type}" unless Summary::TYPES.include?(type)

      input = Input.build(claim, seq, model)
      input_hash = Input.hash(input)
      cached = Summary.find_by(claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id, summary_type: type)
      return present(cached, input_hash) if cached && cached.input_hash == input_hash

      sentences, generator = produce(input, type, adapter)
      row = Summary.upsert(
        { id: SecureRandom.uuid_v7, claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id, summary_type: type,
          input_hash: input_hash, generator: generator, sentences: sentences, created_at: Time.current },
        unique_by: :index_summaries_on_claim_seq_model_type
      )
      present(Summary.find_by!(claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id, summary_type: type), input_hash)
    end

    # The adapter's output must pass the validator; otherwise the stub is served.
    def produce(input, type, adapter)
      sentences = adapter.summarize(input, type: type)
      [ Validator.validate!(sentences, input, type: type), adapter.name ]
    rescue Validator::Invalid, StandardError => e
      Rails.logger.warn("summary generator #{adapter.name} rejected: #{e.message}; serving #{StubGenerator::NAME}")
      [ Validator.validate!(StubGenerator.sentences(input, type: type), input, type: type), StubGenerator::NAME ]
    end

    def present(row, input_hash)
      { claim_id: row.claim_id, snapshot_seq: row.snapshot_seq, model: row.scoring_model.full_name, summary_type: row.summary_type,
        generator: row.generator, input_hash: input_hash, sentences: row.sentences, created_at: row.created_at.utc.iso8601 }
    end
  end
end
