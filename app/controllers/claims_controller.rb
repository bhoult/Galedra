# Claim pages (spec 06 §4 display rules, §5 claim page order).
class ClaimsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_authentication, only: [ :place ]

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
    # Most referenced first (owner request, 2026-09-19): ordered by how often, never by how "wrong" (06 §4 rule 12).
    @since = ClaimReference.since_for(params[:window])
    @counted_kind = ClaimReference::KINDS.include?(params[:kind]) ? params[:kind] : nil
    if params[:sort] == "references"
      top = ClaimReference.top_claim_ids(kind: @counted_kind, since: @since, limit: 500)
      by_id = scope.where(id: top).index_by(&:id)
      claims = top.filter_map { |id| by_id[id] }.first(100)
    else
      claims = scope.limit(100).to_a
    end
    @references = ClaimReference.counts_for(claims.map(&:id), kind: @counted_kind, since: @since)
    scored = selected_model ? Scoring::Score.call_many(claims.to_a, @seq, selected_model) : {}
    @rows = claims.map { |c| [ c, scored[c.id] ] }
    @rows = @rows.select { |_, r| r&.assessment_state == params[:state] } if params[:state].present?
  end

  # Stage 20: file this claim under a section (a signed PLACE_CLAIM).
  def place
    claim = Claim.find(params[:id])
    Ui::Write.call(Current.user, "PLACE_CLAIM", { "claim_id" => claim.id, "section_id" => params[:section_id].to_s })
    redirect_to claim_path(claim, section: params[:section_id]), notice: "Filed. The placement is a signed contribution."
  end

  # The share card (Stage 14): Open Graph tags for link previews and a PNG.
  def card
    @claim = Claim.find(params[:id])
    @seq = head_seq
    raise ActiveRecord::RecordNotFound if Governance::Quarantines.live_for("CLAIM", @claim.id)

    ClaimReference.count!(@claim.id, "SHARED")
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

    ClaimReference.count!(@claim.id, "VIEWED")
    @references = ClaimReference.totals(@claim.id)
    @views = PersonalAssessments::Breakdown.call(@claim.id)
    @inferences = Inferences::View.for_claim(@claim, @seq, @model)
    @sections = Sections::Tree.placements_for(@claim, @seq)
    # The checks this claim was recorded as part of. A reader arriving at one
    # claim usually wants the statement it came out of, which until now was
    # reachable only by the link handed back when it was recorded.
    @checks = Investigation.covering(@claim.id).limit(10).to_a
    @section = (params[:section].present? && @sections.find { |s| s.id == params[:section] }) || @sections.first
    @my_view = authenticated? ? Current.user.personal_assessments.find_by(claim_id: @claim.id) : nil

    @model = selected_model
    @result = @model && Scoring::Score.call(@claim, @seq, @model)
    @card = @model && Cards::ClaimCard.call(@claim, @seq, @model, @result)
    @assessment = @model && Graph::Presenter.assessment(@result, @seq, @model)
    # Stage 34: checks the claim's own author performed. Kept out of the
    # checklist above, which is what independent review means, and shown
    # separately so the page says which it has rather than implying the other.
    @self_checks = Tasks::Checks.self_for(@claim.id, @seq)
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
    # The working, not just the answer: read off the trace and the model's
    # config, computed nowhere (Cards::Calculation).
    @calculation = @show_calculation && @result && @model ? Cards::Calculation.call(@result.trace, @model.config) : nil
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
