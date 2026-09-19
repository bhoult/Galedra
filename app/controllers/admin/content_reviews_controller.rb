# Admin → Content review: the queue of free text awaiting review, what was
# redacted, and the buttons to redact, clear, or restore.
module Admin
  class ContentReviewsController < ApplicationController
    before_action :require_admin

    def index
      @pending = ContentReview.pending.order(:created_at).limit(200)
      @redacted = ContentReview.where(status: "REDACTED").order(reviewed_at: :desc).limit(100)
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
