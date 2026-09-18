# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/custodied/contributions (Stage 12): a write signed by the
    # server for a connected assistant. Body: {action_type, payload}. The
    # response has the shape of POST /contributions.
    class CustodiedController < BaseController
      include AssistantAuth

      before_action :authenticate_assistant!
      before_action { insufficient_scope if read_only_assistant? }
      rate_limit to: 60, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore

      rescue_from Assistants::CapReached do |e|
        render json: { errors: [ { code: "DAILY_CAP", path: "$", detail: e.message } ] }, status: :too_many_requests
      end

      def create
        body = JSON.parse(request.raw_post.presence || "{}")
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "expected {action_type, payload}" } ]) unless body.is_a?(Hash) && body["action_type"].is_a?(String) && body["payload"].is_a?(Hash)

        result = Assistants::Write.call(current_assistant_token, body["action_type"], body["payload"])
        render json: { contribution: Contributions::Presenter.summary(result.contribution),
                       warnings: result.warnings,
                       acceptance: result.acceptance && Contributions::Presenter.summary(result.acceptance) },
               status: result.created ? :created : :ok
      rescue JSON::ParserError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON: #{e.message}" } ])
      end
    end
  end
end
