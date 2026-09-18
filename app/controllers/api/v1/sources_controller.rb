# frozen_string_literal: true

module Api
  module V1
    class SourcesController < BaseController
      def show
        seq = snapshot_seq
        source = Source.find(params[:id])
        model = Scoring::Registry.default_model
        cards = model && !Governance::Quarantines.live_for("SOURCE", source.id) ? Cards::SourceCard.call(source, seq, model) : nil
        render json: { source: Graph::Presenter.source(source), cards: cards }
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
