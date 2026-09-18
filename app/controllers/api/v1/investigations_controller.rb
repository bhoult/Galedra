# frozen_string_literal: true

module Api
  module V1
    # Recording an investigation (Stage 13): a bundle of sources, excerpts,
    # claims, evidence, links, and groups with local handles, recorded as a
    # sequence of custodied contributions, all or nothing.
    #
    # Two doors to the same service. POST /api/v1/investigations with the
    # bundle as the body and the token as a bearer header. GET
    # /api/v1/investigations/record?bundle=... for assistants that can only
    # open links: the bundle is base64url JSON in the query. The token is
    # optional on both: without one the caller is an anonymous assistant keyed
    # to its address for the day. A write on GET is deliberately non-standard
    # (IMPLEMENTATION.md, "The write link"); it is made safe by the rate
    # limits and cap, log filtering, and idempotency: the same assistant and
    # bundle record once.
    class InvestigationsController < BaseController
      include AssistantAuth

      before_action :authenticate_assistant!
      rate_limit to: 20, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore

      rescue_from Assistants::CapReached do |e|
        render json: { errors: [ { code: "DAILY_CAP", path: "$", detail: e.message } ] }, status: :too_many_requests
      end

      def create
        record(JSON.parse(request.raw_post.presence || "{}"))
      rescue JSON::ParserError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON: #{e.message}" } ])
      end

      def record_by_link
        record(decode_bundle(request.path_parameters[:bundle].presence || request.query_parameters["bundle"].to_s))
      end

      private

      def anonymous_assistant_allowed? = true

      def record(bundle)
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "expected a bundle object" } ]) unless bundle.is_a?(Hash)

        digest = InvestigationReceipt.digest_for(bundle)
        if (receipt = InvestigationReceipt.find_by(assistant_token: current_assistant_token, bundle_digest: digest))
          return render json: receipt.result.merge("replayed" => true, "receipt_id" => receipt.id), status: :ok
        end

        result = Investigations::Record.call(current_assistant_token, bundle, base_url: request.base_url)
        if result[:recorded]
          receipt = InvestigationReceipt.create!(id: SecureRandom.uuid_v7, assistant_token: current_assistant_token, bundle_digest: digest, result: result.as_json)
          render json: result.merge(replayed: false, receipt_id: receipt.id), status: :created
        else
          render json: result, status: :conflict
        end
      end

      # The link form carries the bundle as base64url JSON; plain JSON is
      # accepted too, for hand-built links.
      def decode_bundle(text)
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.bundle", detail: "bundle is required: base64url of the investigation JSON" } ]) if text.blank?

        json = text.lstrip.start_with?("{") ? text : Base64.urlsafe_decode64(text.tr(" ", "+"))
        JSON.parse(json)
      rescue ArgumentError, JSON::ParserError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.bundle", detail: "bundle is not base64url JSON: #{e.message}" } ])
      end
    end
  end
end
