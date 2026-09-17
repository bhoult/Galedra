# frozen_string_literal: true

module Api
  module V1
    class SourcesController < BaseController
      def show
        source = Source.find(params[:id])
        render json: { source: Graph::Presenter.source(source) }
      end

      def locations
        seq = snapshot_seq
        source = Source.find(params[:id])
        render json: { source_id: source.id, snapshot_seq: seq,
                       locations: source.source_locations.active_at(seq).order(:created_seq).map { |l| Graph::Presenter.location(l) } }
      end
    end
  end
end
