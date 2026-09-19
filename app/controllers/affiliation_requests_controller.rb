# A person asks for an affiliation the vocabulary lacks (owner request,
# 2026-09-19). Short forms and synonyms are applied at once; the rest waits
# for an admin.
class AffiliationRequestsController < ApplicationController
  def create
    text = params[:text].to_s.strip
    return redirect_to account_path, alert: "Say which affiliation is missing." if text.empty?

    request = AffiliationRequest.file!(user: Current.user, text: text)
    ResolveAffiliationRequestJob.perform_now(request.id) if Rails.env.test?
    request.reload
    notice = request.status == "MERGED" ? "\"#{request.text}\" is #{Affiliations.label(request.resolved_slug)}; it is now on your account." : "Requested. An admin will add it, merge it into an existing affiliation, or decline it; you will see the outcome here."
    redirect_to account_path, notice: notice
  end
end
