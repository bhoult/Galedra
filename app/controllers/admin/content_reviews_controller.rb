# Admin → Content review: the queue of free text awaiting review, what was
# redacted, and the buttons to redact, clear, or restore.
module Admin
  class ContentReviewsController < ApplicationController
    before_action :require_admin

    def index
      # Fifty a page: 186 at once made a page seventy thousand pixels tall on a
      # phone even as cards (2026-09-23).
      @per_page = 50
      @page = params[:page].to_i.clamp(1, 1_000)
      @pending_total = ContentReview.pending.count
      @pending = ContentReview.pending.order(:created_at).offset((@page - 1) * @per_page).limit(@per_page).to_a
      @redacted = ContentReview.where(status: "REDACTED").order(reviewed_at: :desc).limit(100).to_a
      # Both tables asked per row: the verdicts for each pending item, and the
      # reviewer's address for each redacted one. Two queries for the page.
      @consensus = Reviews::Consensus.status_for("ContentReview", @pending.map(&:id))
      @reviewers = User.where(id: @redacted.filter_map(&:reviewed_by_user_id)).pluck(:id, :email_address).to_h
    end

    def settle
      review = ContentReview.find(params[:id])
      review.settle!(params[:outcome].to_s, reason: params[:reason], user: Current.user)
      redirect_to admin_content_reviews_path, notice: review.status == "REDACTED" ? "Redacted." : "Marked clean."
    end

    def restore
      ContentReview.find(params[:id]).restore!(Current.user)
      redirect_to admin_content_reviews_path, notice: "Restored."
    end
  end
end
