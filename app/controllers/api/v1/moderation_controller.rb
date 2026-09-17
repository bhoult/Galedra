# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/moderation?after_seq=&limit= — the public moderation log (spec 05 §13).
    class ModerationController < BaseController
      def index
        entries = Governance::ModerationLog.entries(after_seq: params.fetch(:after_seq, -1).to_i, limit: limit_param(default: 100, max: 1000))
        render json: { entries: entries, appeal_path: Governance::Quarantines::APPEAL_PATH,
                       quarantine_reasons: Quarantine::REASONS, moderator_key_ids: Governance::Moderators.key_ids }
      end
    end
  end
end
