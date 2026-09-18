class WeaknessesController < ApplicationController
  allow_unauthenticated_access

  def index
    @seq = current_seq
    @report = Weaknesses::Report.call(@seq, kind: params[:kind].presence, limit: 25)
  end
end
