# frozen_string_literal: true

module Admin
  # The escape a node with too few principals needs. A thread wants three
  # distinct principals naming one outcome, and a node that does not have three
  # connected people cannot reach that — so an admin settles it by hand, and the
  # page says settled by an admin rather than by agreement, because those are
  # different facts and a reader should see which.
  class ThreadsController < ApplicationController
    before_action :require_admin

    def settle
      thread = DeterminationThread.find(params[:id])
      thread.settle!(params[:outcome].to_s, by_admin: true)
      redirect_back fallback_location: threads_path, notice: "Settled by you as #{params[:outcome].to_s.downcase.tr('_', ' ')}."
    rescue Ledger::Rejected => e
      redirect_back fallback_location: threads_path, alert: e.errors.first[:detail]
    end
  end
end
