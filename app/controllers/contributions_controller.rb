# The log browser and contribution pages (spec 06 §5).
class ContributionsController < ApplicationController
  allow_unauthenticated_access

  def index
    after = params.fetch(:after_seq, -1).to_i
    limit = params.fetch(:limit, 50).to_i.clamp(1, 200)
    scope = Contribution.where("seq > ?", after).in_order
    scope = scope.where(action_type: params[:action_type]) if params[:action_type].present?
    @entries = scope.limit(limit)
    @withheld = Governance::Quarantines.withheld_contribution_ids
    @head = Contribution.maximum(:seq)
  end

  def show
    @contribution = Contribution.find(params[:id])
    @withheld = Governance::Quarantines.withheld_contribution_ids.include?(@contribution.id)
    @verification = Ledger::Verify.entry(@contribution)
    @audits = Contributions::Presenter.audits(@contribution)
    @schedule = Contributions::Presenter.audit_schedule(@contribution)
    @history = Contributions::Presenter.status_history(@contribution)
    @rows = @contribution.projection_rows
  end
end
