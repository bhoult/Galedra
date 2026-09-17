# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/meta (spec 06 §2). Later stages add the current seq, scoring
    # model list, and schema URLs.
    class MetaController < BaseController
      def show
        constitution = Governance::Constitution.new
        render json: {
          constitution_version: constitution.version,
          constitution_hash: constitution.digest,
          system_key_id: Crypto::SystemKey.configured? ? Crypto::SystemKey.key_id : nil,
          system_public_key: Crypto::SystemKey.configured? ? Crypto::SystemKey.public_key : nil
        }
      end
    end
  end
end
