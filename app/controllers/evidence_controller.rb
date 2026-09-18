class EvidenceController < ApplicationController
  allow_unauthenticated_access

  def show
    @seq = current_seq
    @item = EvidenceItem.find(params[:id])
    @evidence = Graph::Presenter.evidence(@item, @seq)
    @audits = Audit.where(target_contribution_id: @item.contribution_id).order(:created_seq)
  end
end
