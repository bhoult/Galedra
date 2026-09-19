# The signed-in person's own account (owner request, 2026-09-19): their
# self-declared affiliations, and the views they have registered on claims.
class AccountsController < ApplicationController
  def show
    @groups = Affiliations.groups
    @mine = Current.user.user_affiliations.pluck(:affiliation)
    @views = Current.user.personal_assessments.includes(:claim).order(updated_at: :desc).limit(100)
    @requests = Current.user.affiliation_requests.order(created_at: :desc).limit(20)
  end

  def update
    picked = Array(params[:affiliations]).map(&:to_s).select { |a| Affiliations.valid?(a) }.uniq
    UserAffiliation.transaction do
      Current.user.user_affiliations.where.not(affiliation: picked).delete_all
      (picked - Current.user.user_affiliations.pluck(:affiliation)).each { |a| Current.user.user_affiliations.create!(affiliation: a) }
    end
    redirect_to account_path, notice: picked.empty? ? "No affiliations recorded." : "Affiliations saved. They are private and appear only in counts."
  end
end
