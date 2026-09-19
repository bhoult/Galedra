class ApplicationController < ActionController::Base
  include Authentication
  include LedgerView
  # The pages need import maps and nothing more exotic; :modern would turn away
  # Safari before 17.2, which is still common on phones.
  allow_browser versions: { safari: 16.4, chrome: 111, firefox: 114, opera: 97, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :admin?, :moderator?

  rescue_from Ledger::Rejected do |e|
    redirect_back fallback_location: root_path, alert: e.errors.map { |x| "#{x[:code]}: #{x[:detail]}" }.join("; ")
  end

  rescue_from Users::Admins::Refused do |e|
    redirect_back fallback_location: root_path, alert: e.message
  end

  private

  # Admin (Stage 24) is a website role: users and menus, never the log.
  def admin?
    authenticated? && Current.user&.admin? || false
  end

  def moderator?
    return false unless authenticated?

    Current.user.moderator? || Governance::Moderators.moderator?(Current.user.contributor)
  end

  def require_admin
    redirect_to root_path, alert: "Admins only." unless admin?
  end
end
