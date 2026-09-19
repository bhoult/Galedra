# frozen_string_literal: true

module Reviews
  # How a review is settled without an admin (owner request, 2026-09-19):
  # REQUIRED verdicts from different principals that agree settle it at once;
  # a single verdict that nobody has contradicted settles it after ALONE_AFTER,
  # so a quiet queue still drains with one honest reviewer. The author of the
  # text never votes on it. Verdicts that disagree wait for a further one to
  # make a pair.
  module Consensus
    REQUIRED = 2
    ALONE_AFTER = 48.hours

    module_function

    # The winning verdict, or nil while undecided.
    def decide(verdicts, now: Time.current)
      return nil if verdicts.empty?

      groups = verdicts.group_by(&:key)
      winner = groups.values.find { |g| g.size >= REQUIRED }
      return winner.first if winner
      return verdicts.first if verdicts.size == 1 && verdicts.first.created_at <= now - ALONE_AFTER

      nil
    end

    def record!(subject_type:, subject_key:, token:, verdict:, detail: {}, reason: nil)
      raise Ledger::Rejected.new([ { code: "NOT_AUTHORIZED", path: "$", detail: "reviewing needs a connected, non-anonymous assistant" } ]) if token.nil? || token.anonymous?

      ReviewVerdict.create!(id: SecureRandom.uuid_v7, subject_type: subject_type, subject_key: subject_key, principal_contributor_id: token.principal_contributor_id,
                            assistant_token_id: token.id, verdict: verdict, detail: detail, reason: reason.presence&.[](0, 200), created_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      raise Ledger::Rejected.new([ { code: "DUPLICATE", path: "$", detail: "this principal has already given a verdict on this item" } ])
    end

    def verdicts_for(subject_type, subject_key)
      ReviewVerdict.where(subject_type: subject_type, subject_key: subject_key).order(:created_at).to_a
    end

    def voted?(subject_type, subject_key, token)
      ReviewVerdict.exists?(subject_type: subject_type, subject_key: subject_key, principal_contributor_id: token.principal_contributor_id)
    end

    def status(subject_type, subject_key)
      verdicts = verdicts_for(subject_type, subject_key)
      { verdicts: verdicts.size, needed: REQUIRED, agreement: verdicts.group_by(&:key).transform_values(&:size) }
    end
  end
end
