# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/log?after_seq=&limit= streams raw entries for mirroring (spec 05 §5).
    class LogController < BaseController
      DEFAULT_LIMIT = 100
      MAX_LIMIT = 1000

      def index
        after_seq = params.fetch(:after_seq, -1).to_i
        limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        entries = Contribution.where("seq > ?", after_seq).in_order.limit(limit)
        render json: { entries: entries.map { |c| Contributions::Presenter.entry(c) }, current_seq: Contribution.maximum(:seq) }
      end
    end
  end
end
