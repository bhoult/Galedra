# A reader's own settings. Nothing here is recorded in the log: a preference
# changes which model's answer a page shows and says nothing about the world.
class PreferencesController < ApplicationController
  allow_unauthenticated_access

  # Signed in, it is kept on the account; signed out, for the length of the
  # session. Either way `?model=` on a link still wins, so a shared link shows
  # the same answer to whoever opens it.
  def model
    name = params[:preferred_model].presence || params[:model].to_s
    chosen = name.present? && Scoring::Registry.released.find_by(full_name_matches(name))
    store(chosen&.full_name)
    redirect_back fallback_location: root_path
  rescue ActiveRecord::StatementInvalid
    redirect_back fallback_location: root_path
  end

  private

  # `full_name` is derived, so it is matched on its parts.
  def full_name_matches(name)
    model, _, version = name.rpartition("@")
    { name: model, semantic_version: version }
  end

  def store(full_name)
    if authenticated?
      Current.user.update(preferred_model: full_name)
    elsif full_name
      session[:preferred_model] = full_name
    else
      session.delete(:preferred_model)
    end
  end
end
