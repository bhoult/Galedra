# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/contributions is the only write path (spec 06 §1).
    class ContributionsController < BaseController
      rate_limit to: 120, within: 1.minute, by: -> { rate_limit_key }, only: :create

      def create
        result = Ledger::Append.call(envelope_from_body)
        render json: { contribution: Contributions::Presenter.summary(result.contribution),
                       warnings: result.warnings,
                       acceptance: result.acceptance && Contributions::Presenter.summary(result.acceptance) },
               status: result.created ? :created : :ok
      end

      def show
        c = Contribution.find(params[:id])
        render json: { contribution: Contributions::Presenter.entry(c), audits: Contributions::Presenter.audits(c),
                       audit_schedule: Contributions::Presenter.audit_schedule(c), status_history: Contributions::Presenter.status_history(c) }
      end

      def verify
        render json: Ledger::Verify.entry(Contribution.find(params[:id]))
      end

      # A moderator convenience: the default redaction manifest for a TAKEDOWN
      # of this contribution, to be edited and signed by the moderator.
      def redaction_manifest
        c = Contribution.find(params[:id])
        raise Ledger::Rejected.new([ { code: "NOT_REDACTABLE", path: "$", detail: "only epistemic contributions can be taken down" } ]) unless c.epistemic?

        render json: { contribution_id: c.id, redaction_manifest: Ledger::Redaction.manifest_for(c),
                       redactable_fields: Ledger::Redaction::REDACTABLE }
      end

      private

      def envelope_from_body
        body = JSON.parse(request.raw_post)
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "envelope must be a JSON object" } ]) unless body.is_a?(Hash)

        body
      rescue JSON::ParserError => e
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON: #{e.message}" } ])
      end

      def rate_limit_key
        JSON.parse(request.raw_post).fetch("signer_key_id", nil).presence || request.remote_ip
      rescue JSON::ParserError, TypeError
        request.remote_ip
      end
    end
  end
end
