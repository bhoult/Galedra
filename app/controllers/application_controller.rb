class ApplicationController < ActionController::Base
  include Authentication
  include LedgerView
  # The pages need import maps and nothing more exotic; :modern would turn away
  # Safari before 17.2, which is still common on phones.
  allow_browser versions: { safari: 16.4, chrome: 111, firefox: 114, opera: 97, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Ledger::Rejected do |e|
    redirect_back fallback_location: root_path, alert: e.errors.map { |x| "#{x[:code]}: #{x[:detail]}" }.join("; ")
  end
end
