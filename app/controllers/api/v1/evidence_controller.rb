# frozen_string_literal: true

module Api
  module V1
    class EvidenceController < BaseController
      def show
        seq = snapshot_seq
        render json: { evidence: Graph::Presenter.evidence(EvidenceItem.find(params[:id]), seq), snapshot_seq: seq }
      end
    end
  end
end
