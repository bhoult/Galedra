# Bug reports (owner request, 2026-09-19). Anyone can file one from the Help
# menu; admins and moderators read them. The text is untrusted and shown
# nowhere else. Assistants file the same thing through the report_bug tool.
class BugReportsController < ApplicationController
  include Triage

  allow_unauthenticated_access only: [ :new, :create ]
  rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip }, only: :create, with: -> { redirect_to new_bug_report_path, alert: "Too many reports from this address. Try again in an hour." }

  def new
    @report = BugReport.new(url: params[:url])
  end

  def create
    attrs = params.require(:bug_report).permit(:happened, :expected, :steps, :url)
    if attrs[:happened].to_s.strip.empty?
      @report = BugReport.new(attrs)
      flash.now[:alert] = "Say what happened."
      return render :new, status: :unprocessable_content
    end

    _, created = BugReport.record!(happened: attrs[:happened], expected: attrs[:expected], steps: attrs[:steps], url: attrs[:url],
                                   user: authenticated? ? Current.user : nil)
    redirect_to root_path, notice: created ? "Thank you. The report is with the maintainers." : "Thank you. The same report was already on file and has been counted again."
  end

  private

  def triage_model = BugReport
  def triage_index_path = bug_reports_path
end
