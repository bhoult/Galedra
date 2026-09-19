# Moderators read what assistants said they could not do (after Stage 19).
# The text is untrusted and is shown nowhere else.
class FeatureRequestsController < ApplicationController
  def index
    contributor = Ui::Write.contributor_for(Current.user)
    return redirect_to root_path, alert: "Moderators only." unless Governance::Moderators.moderator?(contributor)

    @requests = FeatureRequest.order(count: :desc, created_at: :desc).limit(200)
    @since = 30.days.ago
  end
end
