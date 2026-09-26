# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/meta (spec 06 §2). node (Stage 23, spec 14 §25) says which
    # node this is: address, key, protocol and schema versions, data licence,
    # and the software build.
    class MetaController < BaseController
      def show
        constitution = Governance::Constitution.new
        head = Contribution.in_order.last
        render json: {
          constitution_version: constitution.version,
          constitution_hash: constitution.digest,
          # Whether the text served is the one the log last recorded, and where
          # (Article XXV). False means the file changed without an amendment.
          constitution_recorded: (recorded = Governance::Constitution.recorded) ? { seq: recorded[0], version: recorded[1], hash: recorded[2], matches: recorded[2] == constitution.digest } : nil,
          system_key_id: Crypto::SystemKey.configured? ? Crypto::SystemKey.key_id : nil,
          system_public_key: Crypto::SystemKey.configured? ? Crypto::SystemKey.public_key : nil,
          moderator_key_ids: Governance::Moderators.key_ids,
          scoring_models: Scoring::Registry.released.map(&:full_name),
          default_model: Scoring::Registry.default_model&.full_name,
          current_seq: head&.seq,
          chain_head: head&.entry_hash,
          protocol: Ledger::PROTOCOL,
          node: Ledger::Node.to_h,
          schema_urls: Contributions::Schemas::NAMES.to_h { |n| [ n, api_v1_schema_url(n) ] },
          task_types: Tasks::Types::ALL,
          domains: Audits::Policy.domains,
          openapi_url: api_v1_openapi_url(format: :json),
          mcp_url: mcp_url,
          connect_url: new_assistant_url,
          terms_url: terms_url,
          privacy_url: privacy_url,
          takedown_url: takedown_url
        }
      end
    end
  end
end
