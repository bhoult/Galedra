# frozen_string_literal: true

module Api
  module V1
    class OpenapiController < BaseController
      def show
        render json: Api::Openapi.document(request.base_url)
      end
    end
  end
end
