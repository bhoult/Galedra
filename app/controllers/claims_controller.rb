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
    scope = scope.where(id: ClaimTopic.current_at(@seq).where(topic: Topics.paths_under(params[:topic])).select(:claim_id)) if params[:topic].present?
    if params[:source_id].present?
      scope = scope.where(id: EvidenceClaimLink.joins(evidence_item: :source_location).where(source_locations: { source_id: params[:source_id] }).select(:claim_id))
    end
    claims = scope.limit(100).to_a
    @rows = claims.map { |c| [ c, selected_model && Scoring::Score.call(c, @seq, selected_model) ] }
    @rows = @rows.select { |_, r| r&.assessment_state == params[:state] } if params[:state].present?
  end

  # The share card (Stage 14): Open Graph tags for link previews and a PNG.
  def card
    @claim = Claim.find(params[:id])
    @seq = head_seq
    raise ActiveRecord::RecordNotFound if Governance::Quarantines.live_for("CLAIM", @claim.id)

    @model = Scoring::Registry.default_model
    @card = Cards::ClaimCard.call(@claim, @seq, @model)
    @plain = @card[:plain]
    respond_to do |format|
      format.html
      format.png { send_data Cards::Image.render(@claim, @seq, @model, @card), type: "image/png", disposition: "inline" }
    end
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
    @revision = Corrections.status(@claim, @seq)
    @proposals = Corrections.proposals(claim: @claim)
    principal = authenticated? ? Ui::Write.contributor_for(Current.user) : nil
    @acceptable = @proposals.select { |x| principal && Corrections.may_accept?(principal, Contribution.find(x[:contribution_id])) }.map { |x| x[:contribution_id] }
    @history = Contributions::Presenter.status_history(@claim.contribution)
    @link_contributions = Contribution.where(id: @claim.evidence_claim_links.where(arel_lteq(@seq)).select(:contribution_id)).in_order
    @warnings = Claims::Atomicity.warnings(@claim.canonical_text)
    @topics = ClaimTopic.current_at(@seq).where(claim_id: @claim.id).includes(:contribution).order(:created_seq)
    # Rule 1: the number and the trace are rendered only when asked for.
    @show_calculation = params[:calculation].present?
  end

  # A topic suggestion is a signed TAG_CLAIM by the signed-in person (Stage 15).
  def tag
    claim = Claim.find(params[:id])
    topics = Array(params[:topics]).reject(&:blank?).first(Topics::MAX_PER_CLAIM)
    return redirect_to claim_path(claim), alert: "Pick at least one topic." if topics.empty?

    Ui::Write.call(Current.user, "TAG_CLAIM", { "claim_id" => claim.id, "topics" => topics, "note" => params[:note].presence })
    redirect_to claim_path(claim), notice: "Tagged as a signed contribution."
  end

  # Stage 19: a signed-in person accepts a proposed correction on the claim page.
  def accept
    claim = Claim.find(params[:id])
    return redirect_to new_session_path, alert: "Sign in to accept a correction." unless authenticated?

    contribution = Contribution.find(params[:contribution_id])
    principal = Ui::Write.contributor_for(Current.user) || Crypto::Custody.create_server_custodied(user: Current.user, display_name: Current.user.email_address.split("@").first)
    Corrections.accept!(contribution, principal: principal) { |action, payload| Ui::Write.call(Current.user, action, payload) }
    redirect_to claim_path(claim), notice: "Accepted as a signed contribution."
  rescue Ledger::Rejected => e
    redirect_to claim_path(claim), alert: e.errors.map { |x| x[:detail] || x["detail"] }.join("; ")
  end

  private

  def arel_lteq(seq) = EvidenceClaimLink.arel_table[:created_seq].lteq(seq)
end
