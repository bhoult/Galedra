# frozen_string_literal: true

# The maintainer's list for bug reports and feature requests: newest first, one
# page at a time, filtered by status, with a detail view and a way to mark a row
# done or ignored. Both screens behave identically, so the behaviour lives here
# and each controller only says which model it is reading.
module Triage
  extend ActiveSupport::Concern

  PER_PAGE = 100

  included do
    # Named by `only:`, not by excluding the public filing forms: Rails 8 raises
    # ActionNotFound when a callback's `except:` lists an action the controller
    # does not have, and only BugReportsController has new and create. Listing
    # what the guard protects is also the safer direction — a new public action
    # cannot accidentally inherit it.
    before_action :require_triage_access, only: [ :index, :show, :update ]
  end

  def index
    scope = triage_model.newest_first.with_status(params[:status])
    @status = Triageable::STATUSES.include?(params[:status].to_s) ? params[:status].to_s : nil
    @page = params[:page].to_i.clamp(1, 500)
    @total = scope.count
    @counts = triage_model.group(:status).count
    @rows = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @per_page = PER_PAGE
  end

  def show
    @row = triage_model.find(params[:id])
  end

  def update
    row = triage_model.find(params[:id])
    status = params[:status].to_s
    unless Triageable::STATUSES.include?(status)
      return redirect_back fallback_location: triage_index_path, alert: "Unknown status."
    end

    # The resolution is kept when the box is left empty on a later change, so
    # reopening and re-closing does not silently erase the reason given before.
    resolution = params[:resolution].to_s.strip
    row.update!(status: status, resolution: resolution.presence || row.resolution)
    redirect_back fallback_location: triage_index_path, notice: "Marked #{status.downcase}."
  end

  private

  def require_triage_access
    redirect_to root_path, alert: "Moderators and admins only." unless moderator? || admin?
  end
end
