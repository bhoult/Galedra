# frozen_string_literal: true

module Api
  module V1
    class SchemasController < BaseController
      def show
        name = params[:name].to_s
        raise ActiveRecord::RecordNotFound unless Contributions::Schemas::NAMES.include?(name)

        render json: JSON.parse(File.read(Contributions::Schemas::DIR.join("#{name}.json")))
      end
    end
  end
end
