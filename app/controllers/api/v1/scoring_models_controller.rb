# frozen_string_literal: true

module Api
  module V1
    class ScoringModelsController < BaseController
      def index
        default = Scoring::Registry.default_model
        render json: { default: default&.full_name, models: Scoring::Registry.released.map { |m| model(m, default) } }
      end

      private

      def model(m, default)
        { name: m.full_name, config_hash: m.config_hash, code_hash: m.code_hash, released_seq: m.released_seq,
          default: m == default, scored_types: m.config["scored_types"], review_checklist: m.config["review_checklist"], config: m.config }
      end
    end
  end
end
