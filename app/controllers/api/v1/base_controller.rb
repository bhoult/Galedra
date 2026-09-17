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
    end
  end
end
