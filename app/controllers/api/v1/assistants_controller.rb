# frozen_string_literal: true

module Api
  module V1
    # Connected assistants (Stage 12). POST mints a token for an anonymous
    # principal (signed-in minting happens on /assistants/new); DELETE revokes
    # the caller's own token, which appends REVOKE_DELEGATION.
    class AssistantsController < BaseController
      include AssistantAuth

      rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip }, only: :create, with: -> { too_many_requests }, store: Assistants::RateLimitStore
      before_action :authenticate_assistant!, only: :destroy

      def create
        body = JSON.parse(request.raw_post.presence || "{}")
        assistant = body.fetch("assistant", {})
        record, plaintext = Assistants::Connect.call(name: assistant["name"], provider: assistant["provider"], model: assistant["model"])
        render json: { token: plaintext, assistant: Assistants::Presenter.call(record) }, status: :created
      rescue JSON::ParserError, ArgumentError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.assistant", detail: e.message } ])
      end

      def destroy
        token = current_assistant_token
        raise Ledger::Rejected.new([ { code: "NOT_AUTHORIZED", path: "$", detail: "a token can only revoke itself" } ]) unless token.id == params[:id]

        render json: { assistant: Assistants::Presenter.call(Assistants::Revoke.call(token)) }
      end
    end
  end
end
