# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/investigations (Stage 13): a bundle of sources, excerpts,
    # claims, evidence, links, and groups with local handles, recorded as a
    # sequence of custodied contributions, all or nothing.
    class InvestigationsController < BaseController
      include AssistantAuth

      before_action :authenticate_assistant!
      rate_limit to: 20, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore

      rescue_from Assistants::CapReached do |e|
        render json: { errors: [ { code: "DAILY_CAP", path: "$", detail: e.message } ] }, status: :too_many_requests
      end

      def create
        bundle = JSON.parse(request.raw_post.presence || "{}")
        result = Investigations::Record.call(current_assistant_token, bundle, base_url: request.base_url)
        render json: result, status: result[:recorded] ? :created : :conflict
      rescue JSON::ParserError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON: #{e.message}" } ])
      end
    end
  end
end
