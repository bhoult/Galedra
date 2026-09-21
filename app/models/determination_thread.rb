# frozen_string_literal: true

# A conversation about how a determination was made (Stage 37, owner request
# 2026-09-20). It hangs on a claim, a link, an evidence item, a source location
# or a task result, and its turns say things like: this statement's figures are
# not in the passage it rests on; these two sources may share an origin; these
# two items answer different questions and the card does not say so.
#
# **A thread guides evidence gathering; it does not determine it.** Nothing here
# is read by the scorer, nothing carries a version, and a thread that is wrong
# costs the record nothing. Its whole product is a decision about what somebody
# should go and check, which is why settling it acts on the work queue and never
# on the evidence chain.
#
# A turn about the world is not a thread turn. "This claim is false, and here is
# a source" is a contribution; the thread is for how the determination was made.
class DeterminationThread < ApplicationRecord
  include FilingCap

  # What three principals may agree on. INVESTIGATE raises work given the
  # discovered facts; NO_FURTHER_WORK says this no longer needs to be an open
  # work task. Both are about what should be done next, never about what is true.
  OUTCOMES = %w[INVESTIGATE NO_FURTHER_WORK].freeze
  STATUSES = %w[OPEN SETTLED RETIRED].freeze
  REQUIRED = 3
  # Silence, not a conclusion. A thread nobody has touched leaves the work list
  # so it does not clog next_thread, and any new turn revives it with its turns
  # and votes intact. The register's timeout closes a report, which reads as a
  # conclusion when it is really an absence; this one says what happened.
  RETIRE_AFTER = 14.days
  WINDOW = 30.days
  SUBJECTS = %w[Claim EvidenceClaimLink EvidenceItem SourceLocation TaskAssignment].freeze
  MAX_CHARS = 5_000

  belongs_to :assistant_token, optional: true
  belongs_to :user, optional: true
  belongs_to :cites, class_name: "DeterminationThread", foreign_key: :cites_thread_id, optional: true, inverse_of: false
  has_many :turns, class_name: "ThreadTurn", as: :thread, dependent: :destroy, inverse_of: :thread

  validates :status, inclusion: { in: STATUSES }
  validates :subject_type, inclusion: { in: SUBJECTS }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :concern, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :open_threads, -> { where(status: "OPEN") }
  scope :with_status, ->(value) { STATUSES.include?(value.to_s) ? where(status: value.to_s) : all }

  def open? = status == "OPEN"
  def settled? = status == "SETTLED"
  def retired? = status == "RETIRED"

  def subject = subject_type.constantize.find_by(id: subject_id)

  def self.digest_for(subject_type, subject_id, concern)
    Digest::SHA256.hexdigest([ subject_type, subject_id, concern.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip ].join("\u0000"))
  end

  # Opening one. The digest spans settled threads as well as open ones: the same
  # concern raised again is counted on the thread that already answered it, where
  # a reader can see it was raised twice, rather than starting the argument over.
  def self.record!(subject:, concern:, token: nil, user: nil, cites: nil)
    refuse_if_over_cap!(token, "threads") if token
    raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.subject", detail: "expected one of #{SUBJECTS.join(', ')}" } ]) unless SUBJECTS.include?(subject.class.name)

    digest = digest_for(subject.class.name, subject.id, concern)
    if (existing = where(digest: digest).where("created_at >= ?", WINDOW.ago).order(:created_at).first)
      existing.update!(count: existing.count + 1)
      return [ existing, false ]
    end
    text = concern.to_s.strip
    [ create!(id: SecureRandom.uuid_v7, subject_type: subject.class.name, subject_id: subject.id, concern: text[0, MAX_CHARS],
              assistant_token: token, user: user, opener_principal_id: token&.principal_contributor_id || user&.contributor&.id,
              anonymous: token ? token.anonymous? : false, digest: digest, cites_thread_id: cites&.id, last_turn_at: Time.current)
        .tap { |t| ContentReview.enqueue!(t) }, text.length > MAX_CHARS ]
  end

  # A turn, and optionally a vote with it.
  #
  # The turn always lands. A vote that cannot count — because this principal has
  # already voted, or because the thread is settled, or because an anonymous
  # token has no principal to attribute it to — does not take the turn down with
  # it: saying something more is always allowed, and only the counting is
  # restricted. The reply says which happened rather than leaving the caller to
  # infer it from a number that did not move.
  #
  # Clipped rather than refused: a caller told its prose was too long by an
  # exception has lost the prose.
  def respond!(body:, token: nil, user: nil, verdict: nil)
    text = body.to_s.strip
    raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.verdict", detail: "expected one of #{OUTCOMES.join(', ')}" } ]) if verdict.present? && !OUTCOMES.include?(verdict)

    vote = verdict.present? ? record_vote(token: token, user: user, verdict: verdict) : :none
    transaction do
      turns.create!(author_kind: user ? "maintainer" : "assistant", assistant_token: token, user: user,
                    body: text[0, MAX_CHARS], verdict: (verdict if vote == :counted), created_at: Time.current)
      # A retired thread is dormant, not concluded: any turn revives it with its
      # turns and votes intact.
      update!(status: (retired? ? "OPEN" : status), last_turn_at: Time.current)
    end
    settle_if_agreed! if vote == :counted
    { clipped: text.length > MAX_CHARS, vote: vote }
  end

  # One vote per principal, whoever cast it. A person writing directly and that
  # person's assistant writing for them are the same principal, which is the
  # whole point of counting principals rather than tokens.
  def record_vote(token:, user:, verdict:)
    # An anonymous token has a contributor but no person behind it, so it has
    # nobody to be one of the three. It may speak; it cannot count.
    return :unattributable if token&.anonymous?

    principal = token&.principal_contributor_id || user&.contributor&.id
    return :unattributable if principal.nil?
    return :already_settled if settled?

    ReviewVerdict.create!(id: SecureRandom.uuid_v7, subject_type: self.class.name, subject_key: id, principal_contributor_id: principal,
                          assistant_token_id: token&.id, verdict: verdict, created_at: Time.current)
    :counted
  rescue ActiveRecord::RecordNotUnique
    :already_voted
  end

  VOTE_NOTES = {
    counted: "Your vote is counted.",
    already_voted: "Your turn is recorded; your principal had already voted on this thread and a principal votes once.",
    already_settled: "Your turn is recorded; the thread was already settled, so the vote does not count.",
    unattributable: "Your turn is recorded; a vote needs a principal, so an anonymous assistant may speak but not count.",
    none: nil
  }.freeze

  def votes = ReviewVerdict.where(subject_type: self.class.name, subject_key: id).order(:created_at).to_a

  def tally = votes.group_by(&:verdict).transform_values(&:size)

  # Three distinct principals naming the same outcome. A two-two split does not
  # settle; it waits for a fourth, because agreement is the thing being counted
  # and a majority is not agreement.
  def settle_if_agreed!
    return self if settled?

    winner = tally.find { |_, n| n >= REQUIRED }
    return self if winner.nil?

    settle!(winner.first)
  end

  def settle!(chosen, by_admin: false)
    raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.outcome", detail: "expected one of #{OUTCOMES.join(', ')}" } ]) unless OUTCOMES.include?(chosen)

    transaction do
      update!(status: "SETTLED", outcome: chosen, settled_at: Time.current)
      Threads::Settle.call(self, by_admin: by_admin)
    end
    self
  end

  # The split, because three agreeing when two disagreed is a different fact from
  # three agreeing unopposed, and a reader weighing a settlement should see which.
  def split
    return nil unless settled?

    counts = tally
    [ counts[outcome].to_i, counts.reject { |k, _| k == outcome }.values.sum ]
  end

  def dissenters = votes.select { |v| v.verdict != outcome }

  # Whether the subject is still the current version of itself. A thread on a
  # merged claim is history and stays readable; it simply stops being work.
  def subject_current?
    row = subject
    return false if row.nil?
    return row.status == "ACTIVE" if row.respond_to?(:status) && row.is_a?(Claim)
    return !row.invalidated? if row.respond_to?(:invalidated?)

    true
  end

  def workable? = open? && subject_current?

  def state_badge
    case status
    when "OPEN"
      subject_current? ? [ "needs-you", "●", "open", "Open. #{REQUIRED - (tally.values.max || 0)} more principal(s) agreeing on one outcome settles it." ]
                       : [ "aside", "–", "stale", "Open, but what it hangs on is no longer current. Kept as history; it is not offered as work." ]
    when "SETTLED"
      agreed, against = split
      [ "agreed", "✓", outcome == "INVESTIGATE" ? "investigate" : "settled",
        "Settled #{agreed}–#{against} as #{outcome.downcase.tr('_', ' ')}#{' by an admin' if outcome && settled_at && votes.size < REQUIRED}." ]
    when "RETIRED"
      [ "lapsed", "○", "retired", "Retired after #{RETIRE_AFTER.inspect} of silence. Nothing was agreed; any turn revives it." ]
    else
      [ "other", "·", status.downcase, status.downcase ]
    end
  end

  def state_line = state_badge.last

  # Silence, swept. Never applied to a settled thread, which has a conclusion.
  def self.retire_silent!(now: Time.current)
    open_threads.where("COALESCE(last_turn_at, created_at) <= ?", now - RETIRE_AFTER).find_each do |row|
      row.update!(status: "RETIRED")
    end
  end
end
