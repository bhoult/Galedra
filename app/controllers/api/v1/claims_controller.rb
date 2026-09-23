# frozen_string_literal: true

module Api
  module V1
    class ClaimsController < BaseController
      # GET /api/v1/claims?type=&status=&state=&q=&similar_to=&model=&limit=&sort=&kind=&window=
      # Lists accepted, live claims (proposals are reachable by id only).
      # state= filters on the assessment state under the chosen model.
      # sort=references orders by how often claims were referenced (kind= one of
      # ClaimReference::KINDS, window= 7d|30d|365d): attention, never truth or error.
      def index
        seq = snapshot_seq
        claims = if params[:similar_to].present?
          Claims::Duplicates.candidates(Claim.find(params[:similar_to]).canonical_text, exclude_id: params[:similar_to])
        else
          scope = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(created_seq: :desc)
          scope = scope.where(claim_type: params[:type]) if params[:type].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where("to_tsvector('english', canonical_text) @@ plainto_tsquery('english', ?)", params[:q]) if params[:q].present?
          scope = scope.where(id: ClaimTopic.current_at(seq).where(topic: Topics.paths_under(params[:topic])).select(:claim_id)) if params[:topic].present?
          if params[:sort] == "references"
            kind = ClaimReference::KINDS.include?(params[:kind]) ? params[:kind] : nil
            top = ClaimReference.top_claim_ids(kind: kind, since: ClaimReference.since_for(params[:window]), limit: 500)
            by_id = scope.where(id: top).index_by(&:id)
            top.filter_map { |id| by_id[id] }.first(limit_param(default: 50, max: 200))
          else
            scope.limit(limit_param(default: 50, max: 200))
          end
        end
        claims = claims.to_a
        # Presented as a page, not claim by claim (Stage 26).
        presented = Graph::Presenter.claims(claims, seq, model: model)
        rendered = claims.zip(presented).map { |c, p| p.merge(similarity: c.try(:similarity)).compact }
        rendered = rendered.select { |c| c.dig(:assessment, :assessment_state) == params[:state] } if params[:state].present?
        render json: { snapshot_seq: seq, model: model&.full_name, claims: rendered }
      end

      def show
        seq = snapshot_seq
        claim = Claim.find(params[:id])
        raise ActiveRecord::RecordNotFound if claim.created_seq > seq

        render json: { claim: Graph::Presenter.claim(claim, seq, model: model), warnings: Claims::Atomicity.warnings(claim.canonical_text) }
      end

      # GET /api/v1/claims/:id/views: registered personal views in aggregate
      # (spec 02 §3.6a, Article XV). Counts only; affiliations only for groups
      # of PersonalAssessments::Breakdown::MIN_GROUP or more; never a score input.
      def views
        claim = Claim.find(params[:id])
        render json: { claim_id: claim.id, views: PersonalAssessments::Breakdown.call(claim.id) }
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
