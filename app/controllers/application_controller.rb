class ApplicationController < ActionController::Base
  include Authentication
  include LedgerView
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Ledger::Rejected do |e|
    redirect_back fallback_location: root_path, alert: e.errors.map { |x| "#{x[:code]}: #{x[:detail]}" }.join("; ")
  end
end
