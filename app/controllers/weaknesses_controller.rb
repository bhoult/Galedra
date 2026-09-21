class WeaknessesController < ApplicationController
  allow_unauthenticated_access

  def index
    @seq = current_seq
    # The page builds one "what would most change this" per row it shows, so how
    # many rows it shows is what it costs (Stage 39). The API has taken a limit
    # since Stage 26; the page now takes the same one.
    @per_page = params[:limit].present? ? params[:limit].to_i.clamp(1, 50) : 25
    @page = params[:page].to_i.clamp(1, 20)
    @report = Weaknesses::Report.call(@seq, kind: params[:kind].presence, limit: @per_page, offset: (@page - 1) * @per_page)
  end
end
