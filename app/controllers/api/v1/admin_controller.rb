# frozen_string_literal: true

module Api
  module V1
    # Moderator-only operations (spec 06 §2), authenticated by a signed body.
    class AdminController < BaseController
      before_action :verify_admin!

      def create_snapshot
        seq = Integer(@payload["seq"], exception: false)
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.payload.seq", detail: "expected an integer" } ]) if seq.nil?

        snapshot = Snapshots::Create.call(seq: seq, label: @payload["label"])
        render json: { snapshot: { seq: snapshot.seq, entry_hash: snapshot.entry_hash, label: snapshot.label } }, status: :created
      end

      def recompute
        RecomputeAllScoresJob.perform_later(Contribution.maximum(:seq))
        render json: { enqueued: "RecomputeAllScoresJob", seq: Contribution.maximum(:seq) }, status: :accepted
      end

      private

      def verify_admin!
        @payload = Admin::Request.verify!(JSON.parse(request.raw_post))
      rescue JSON::ParserError
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON" } ])
      end
    end
  end
end
