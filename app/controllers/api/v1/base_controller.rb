# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      rescue_from Ledger::Rejected do |e|
        render json: { errors: e.errors }, status: 422
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { errors: [ { code: "NOT_FOUND", path: "$", detail: "no such record" } ] }, status: :not_found
      end

      private

      # ?snapshot_seq= defaults to the log head (spec 06 §2).
      def snapshot_seq
        head = Contribution.maximum(:seq) || 0
        return head if params[:snapshot_seq].blank?

        seq = Integer(params[:snapshot_seq], exception: false)
        if seq.nil? || seq.negative? || seq > head
          raise Ledger::Rejected.new([ { code: "SNAPSHOT_UNKNOWN", path: "$.snapshot_seq", detail: "expected an integer in 0..#{head}" } ])
        end
        seq
      end

      def limit_param(default:, max:)
        params.fetch(:limit, default).to_i.clamp(1, max)
      end
    end
  end
end
