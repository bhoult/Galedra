# frozen_string_literal: true

module Api
  module V1
    class ClaimsController < BaseController
      # GET /api/v1/claims?type=&status=&state=&q=&similar_to=&model=&limit=
      # Lists accepted, live claims (proposals are reachable by id only).
      # state= filters on the assessment state under the chosen model.
      def index
        seq = snapshot_seq
        claims = if params[:similar_to].present?
          Claims::Duplicates.candidates(Claim.find(params[:similar_to]).canonical_text, exclude_id: params[:similar_to])
        else
          scope = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(created_seq: :desc)
          scope = scope.where(claim_type: params[:type]) if params[:type].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where("to_tsvector('english', canonical_text) @@ plainto_tsquery('english', ?)", params[:q]) if params[:q].present?
          scope.limit(limit_param(default: 50, max: 200))
        end
        rendered = claims.map { |c| Graph::Presenter.claim(c, seq, model: model).merge(similarity: c.try(:similarity)).compact }
        rendered = rendered.select { |c| c.dig(:assessment, :assessment_state) == params[:state] } if params[:state].present?
        render json: { snapshot_seq: seq, model: model&.full_name, claims: rendered }
      end

      def show
        seq = snapshot_seq
        claim = Claim.find(params[:id])
        raise ActiveRecord::RecordNotFound if claim.created_seq > seq

        render json: { claim: Graph::Presenter.claim(claim, seq, model: model), warnings: Claims::Atomicity.warnings(claim.canonical_text) }
      end

      def evidence
        seq = snapshot_seq
        render json: Graph::Presenter.claim_evidence(Claim.find(params[:id]), seq)
      end

      private

      def model
        return @model if defined?(@model)

        @model = params[:model].present? ? Scoring::Registry.find(params[:model]) : Scoring::Registry.default_model
      rescue Scoring::Registry::Invalid => e
        raise Ledger::Rejected.new([ { code: "MODEL_UNKNOWN", path: "$.model", detail: e.message } ])
      end
    end
  end
end
