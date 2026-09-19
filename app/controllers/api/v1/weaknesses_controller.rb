# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/weaknesses?kind=&limit=&snapshot_seq= (spec 06 §5, Art. XXII).
    class WeaknessesController < BaseController
      def index
        render json: Weaknesses::Report.call(snapshot_seq, kind: params[:kind].presence,
                                             limit: limit_param(default: 50, max: 200), offset: params[:offset].to_i)
      end
    end
  end
end
