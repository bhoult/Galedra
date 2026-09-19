class WeaknessesController < ApplicationController
  allow_unauthenticated_access

  def index
    @seq = current_seq
    @per_page = 25
    @page = params[:page].to_i.clamp(1, 20)
    @report = Weaknesses::Report.call(@seq, kind: params[:kind].presence, limit: @per_page, offset: (@page - 1) * @per_page)
  end
end
