# /adopt/:code (IMPLEMENTATION.md, "Adoption"): a signed-in person puts an
# anonymous assistant's work under their own key with one click. Signing in
# first is required; the person is sent back here afterwards.
class AdoptionsController < ApplicationController
  before_action :load_token

  def show
    @claims = Claim.where(contribution_id: Contribution.where(signer_key_id: @token.agent.key_id).select(:id)).order(created_seq: :desc).limit(20)
    @count = Contribution.where(signer_key_id: @token.agent.key_id, action_class: Contribution::EPISTEMIC).count
  end

  def create
    contribution = Assistants::Adopt.call(@token, Current.user)
    redirect_to contributor_path(@token.principal), notice: "Done. This work is now under your name; the adoption is entry #{contribution.seq} in the public log."
  rescue Assistants::Adopt::NotAdoptable, Ledger::Rejected => e
    redirect_to adopt_path(params[:code]), alert: e.respond_to?(:errors) ? e.errors.map { |x| x[:detail] }.join("; ") : e.message
  end

  private

  def load_token
    @token = AssistantToken.find_by(adoption_digest: AssistantToken.digest(params[:code]))
    raise ActiveRecord::RecordNotFound if @token.nil?
  end
end
