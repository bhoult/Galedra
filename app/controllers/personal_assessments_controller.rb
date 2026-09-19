# Thumbs up or down on a claim (spec 02 §3.6a, Article XV): the person's own
# view, kept outside the log and shown in its own labelled panel.
class PersonalAssessmentsController < ApplicationController
  def create
    claim = Claim.find(params[:claim_id])
    stance = params[:stance].to_s
    return redirect_to claim_path(claim), alert: "Agree or disagree." unless PersonalAssessment::STANCES.include?(stance)

    PersonalAssessment.set!(user: Current.user, claim: claim, stance: stance, rationale: params[:rationale])
    redirect_to claim_path(claim, anchor: "your-view"), notice: "Your view is recorded. It is yours, not Galedra's assessment."
  end

  def destroy
    claim = Claim.find(params[:claim_id])
    Current.user.personal_assessments.where(claim: claim).delete_all
    redirect_to claim_path(claim, anchor: "your-view"), notice: "Your view is removed."
  end
end
