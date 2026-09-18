class ModerationController < ApplicationController
  allow_unauthenticated_access

  def index
    @entries = Governance::ModerationLog.entries(after_seq: params.fetch(:after_seq, -1).to_i, limit: 200)
    @moderators = Governance::Moderators.key_ids
  end
end
