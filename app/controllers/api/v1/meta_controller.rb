# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/meta (spec 06 §2). Later stages add the scoring model list
    # and schema URLs.
    class MetaController < BaseController
      def show
        constitution = Governance::Constitution.new
        head = Contribution.in_order.last
        render json: {
          constitution_version: constitution.version,
          constitution_hash: constitution.digest,
          system_key_id: Crypto::SystemKey.configured? ? Crypto::SystemKey.key_id : nil,
          system_public_key: Crypto::SystemKey.configured? ? Crypto::SystemKey.public_key : nil,
          moderator_key_ids: Governance::Moderators.key_ids,
          scoring_models: Scoring::Registry.released.map(&:full_name),
          default_model: Scoring::Registry.default_model&.full_name,
          current_seq: head&.seq,
          chain_head: head&.entry_hash,
          protocol: Ledger::PROTOCOL,
          schema_urls: Contributions::Schemas::NAMES.to_h { |n| [ n, api_v1_schema_url(n) ] },
          task_types: Tasks::Types::ALL,
          domains: Audits::Policy.domains,
          openapi_url: api_v1_openapi_url(format: :json),
          mcp_url: mcp_url,
          connect_url: new_assistant_url
        }
      end
    end
  end
end
