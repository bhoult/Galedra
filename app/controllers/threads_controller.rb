# frozen_string_literal: true

# Threads on determinations (Stage 37). One index of every thread on the node,
# because a thread hangs off five kinds of object and the page each one lives on
# is not enough by itself: a reader would have to already know where to look.
#
# Anyone may read. A signed-in person may take a turn, and it counts as their
# principal — which means their own assistant's turn is the same principal and
# does not count twice. An anonymous visitor reads and does not write: a turn
# that counts toward consensus has to belong to somebody.
class ThreadsController < ApplicationController
  allow_unauthenticated_access only: [ :index, :show ]

  PER_PAGE = 100

  def index
    scope = DeterminationThread.newest_first.with_status(params[:status])
    @status = DeterminationThread::STATUSES.include?(params[:status].to_s) ? params[:status].to_s : nil
    @page = params[:page].to_i.clamp(1, 500)
    @total = scope.count
    @counts = DeterminationThread.group(:status).count
    @rows = scope.includes(:turns).offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @per_page = PER_PAGE
  end

  def show
    @row = DeterminationThread.find(params[:id])
  end

  def create
    subject = DeterminationThread::SUBJECTS.include?(params[:subject_type].to_s) &&
              params[:subject_type].to_s.constantize.find_by(id: params[:subject_id].to_s)
    return redirect_back fallback_location: threads_path, alert: "Unknown subject." unless subject
    return redirect_back fallback_location: threads_path, alert: "Say what is wrong with how this was made." if params[:concern].to_s.strip.empty?

    thread, = DeterminationThread.record!(subject: subject, concern: params[:concern], user: Current.user)
    redirect_to thread_path(thread), notice: thread.count > 1 ? "That concern was already open here; yours is counted on it." : "Thread opened."
  end

  def respond
    row = DeterminationThread.find(params[:id])
    return redirect_to thread_path(row), alert: "Say something in the reply." if params[:body].to_s.strip.empty?

    result = row.respond!(body: params[:body], user: Current.user, verdict: params[:verdict].presence)
    redirect_to thread_path(row), notice: [ "Recorded.", DeterminationThread::VOTE_NOTES[result[:vote]] ].compact.join(" ")
  rescue Ledger::Rejected => e
    redirect_to thread_path(row), alert: e.errors.first[:detail]
  end
end
