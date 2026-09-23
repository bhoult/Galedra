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
    @status = Triageable::VIEWS.include?(params[:status].to_s) ? params[:status].to_s : nil
    @page = params[:page].to_i.clamp(1, 500)
    @total = scope.count
    # HELD is carved out of ANSWERED rather than added beside it, so the filter's
    # numbers still sum to the whole and a held report is not counted twice.
    @counts = triage_model.group(:status).count
    held = triage_model.held.count
    @counts["HELD"] = held
    @counts["ANSWERED"] = @counts.fetch("ANSWERED", 0) - held
    # The turns come with the rows: the list says whose turn each one is, and
    # asking per row would be a query each.
    @rows = scope.includes(:turns).offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @per_page = PER_PAGE
  end

  def show
    @row = triage_model.find(params[:id])
  end

  def update
    row = triage_model.find(params[:id])
    status = params[:status].to_s
    unless Triageable::VIEWS.include?(status)
      return redirect_back fallback_location: triage_index_path, alert: "Unknown status."
    end

    # HELD is a kind of answer, not a status of its own: it hands the report back
    # and says the timeout must not close it, because the work it agreed to has
    # not been done.
    settles = status != "HELD"
    status = "ANSWERED" unless settles

    # The resolution is kept when the box is left empty on a later change, so
    # reopening and re-closing does not silently erase the reason given before.
    # What is new is that an answer is also a turn in the exchange: the reporter
    # reads it, says whether it settles the thing, and only their verdict reaches
    # CLOSED (owner request, 2026-09-20).
    resolution = params[:resolution].to_s.strip
    # Handing a report back with nothing said, and nothing said before, leaves the
    # reporter nothing to agree or disagree with. Handing it back again after an
    # earlier answer is fine: that answer is still in the thread.
    if status == "ANSWERED" && resolution.blank? && row.resolution.blank?
      return redirect_back fallback_location: triage_index_path,
                           alert: "Say something in the reply: answering hands the report back, and an empty answer gives the reporter nothing to respond to."
    end

    row.answer!(body: resolution, user: Current.user, status: status, settles: settles,
                fixed_in: params[:fixed_in].to_s.strip, repro: params[:repro].to_s.strip)
    redirect_back fallback_location: triage_index_path, notice: notice_for(settles ? status : "HELD")
  end

  private

  def notice_for(status)
    case status
    when "ANSWERED" then "Answered. The reporter sees it as their turn and can say whether it settles the thing."
    when "HELD" then "Held. It stays open however long the silence, because you have agreed to work that is not done."
    when "CLOSED" then "Closed. Normally the reporter closes it by agreeing; closing it here says so on their behalf."
    else "Marked #{status.downcase}."
    end
  end

  def require_triage_access
    redirect_to root_path, alert: "Moderators and admins only." unless moderator? || admin?
  end
end
