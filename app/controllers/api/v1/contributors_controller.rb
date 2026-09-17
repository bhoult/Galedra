# frozen_string_literal: true

module Api
  module V1
    class ContributorsController < BaseController
      def show
        render json: { contributor: Graph::Presenter.contributor(Contributor.find(params[:id])) }
      end
    end
  end
end
