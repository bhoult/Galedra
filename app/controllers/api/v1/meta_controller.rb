# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/meta (spec 06 §2). Later stages add the system key, current
    # seq, scoring model list, and schema URLs.
    class MetaController < BaseController
      def show
        constitution = Governance::Constitution.new
        render json: {
          constitution_version: constitution.version,
          constitution_hash: constitution.digest
        }
      end
    end
  end
end
