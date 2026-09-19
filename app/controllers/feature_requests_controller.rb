# Moderators and admins read what assistants said they could not do (after
# Stage 19). The text is untrusted and is shown nowhere else.
class FeatureRequestsController < ApplicationController
  def index
    return redirect_to root_path, alert: "Moderators and admins only." unless moderator? || admin?

    @requests = FeatureRequest.order(count: :desc, created_at: :desc).limit(200)
    @since = 30.days.ago
  end
end
