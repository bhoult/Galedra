# Claim pages (spec 06 §4 display rules, §5 claim page order).
class ClaimsController < ApplicationController
  allow_unauthenticated_access

  def index
    @seq = current_seq
    scope = Claim.counted_at(@seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(created_seq: :desc)
    scope = scope.where(claim_type: params[:type]) if params[:type].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("to_tsvector('english', canonical_text) @@ plainto_tsquery('english', ?)", params[:q]) if params[:q].present?
    scope = scope.where(contribution_id: Contribution.where(contributor_id: params[:contributor_id]).select(:id)) if params[:contributor_id].present?
    if params[:source_id].present?
      scope = scope.where(id: EvidenceClaimLink.joins(evidence_item: :source_location).where(source_locations: { source_id: params[:source_id] }).select(:claim_id))
    end
    claims = scope.limit(100).to_a
    @rows = claims.map { |c| [ c, selected_model && Scoring::Score.call(c, @seq, selected_model) ] }
    @rows = @rows.select { |_, r| r&.assessment_state == params[:state] } if params[:state].present?
  end

  def show
    @seq = current_seq
    @claim = Claim.find(params[:id])
    raise ActiveRecord::RecordNotFound if @claim.created_seq > @seq

    @quarantine = Governance::Quarantines.live_for("CLAIM", @claim.id)
    return if @quarantine

    @model = selected_model
    @result = @model && Scoring::Score.call(@claim, @seq, @model)
    @card = @model && Cards::ClaimCard.call(@claim, @seq, @model, @result)
    @assessment = @model && Graph::Presenter.assessment(@result, @seq, @model)
    @why = @model && Cards::Why.call(@claim, @seq, @model)
    @evidence = Graph::Presenter.claim_evidence(@claim, @seq)
    @summary = @model && Summaries::Generate.call(@claim, @seq, @model, type: "STANDARD")
    @evaluable, @reason = @claim.evaluability_at(@seq)
    @history = Contributions::Presenter.status_history(@claim.contribution)
    @link_contributions = Contribution.where(id: @claim.evidence_claim_links.where(arel_lteq(@seq)).select(:contribution_id)).in_order
    @warnings = Claims::Atomicity.warnings(@claim.canonical_text)
    # Rule 1: the number and the trace are rendered only when asked for.
    @show_calculation = params[:calculation].present?
  end

  private

  def arel_lteq(seq) = EvidenceClaimLink.arel_table[:created_seq].lteq(seq)
end
