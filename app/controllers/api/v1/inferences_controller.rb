# frozen_string_literal: true

module Api
  module V1
    # One inference (Stage 25): premises with their current states, the weakest marked. Never a score for the step.
    class InferencesController < BaseController
      def show
        seq = snapshot_seq
        inference = Inference.find(params[:id])
        raise ActiveRecord::RecordNotFound unless inference.active_at?(seq)

        render json: { snapshot_seq: seq, inference: Inferences::View.present(inference, seq, Scoring::Registry.default_model), note: Inference::NOTE }
      end
    end
  end
end
