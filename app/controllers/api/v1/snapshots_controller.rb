# frozen_string_literal: true

module Api
  module V1
    class SnapshotsController < BaseController
      def index
        render json: { snapshots: GraphSnapshot.order(:seq).map { |s| snapshot(s) }, current_seq: Contribution.maximum(:seq) }
      end

      # Any seq can be read; only POST /admin/snapshots pins one.
      def show
        seq = Integer(params[:seq], exception: false)
        entry = seq && Contribution.find_by(seq: seq)
        raise ActiveRecord::RecordNotFound if entry.nil?

        pinned = GraphSnapshot.find_by(seq: seq)
        snapshot = pinned || GraphSnapshot.new(seq: seq, entry_hash: entry.entry_hash)
        model = Scoring::Registry.default_model
        render json: snapshot(snapshot).merge(model: model&.full_name, claim_score_digest: model && Snapshots::Digest.call(seq, model: model),
                                              pinned: pinned.present?)
      end

      private

      def snapshot(s)
        { seq: s.seq, entry_hash: s.entry_hash, label: s.label, created_at: s.created_at&.utc&.iso8601, checkpoint: s.checkpoint }
      end
    end
  end
end
