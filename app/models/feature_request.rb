# What an assistant wanted to do with Galedra and could not, in its own words
# at the moment it failed (owner request, after Stage 19). Outside the log:
# untrusted text, shown only to moderators, never to other assistants or the
# public. Repeats of the same need within a month are counted, not duplicated.
class FeatureRequest < ApplicationRecord
  include Triageable
  # 2,000 to match BugReport, and `expected` gets the same room as the rest.
  # It was 200, which is where an assistant says what it actually wants, and
  # every request filed in the 2026-09-20 run was cut off mid-sentence there —
  # nine of nine — with nothing said about it
  # (docs/experiments/2026-09-20-second-connector-run.md).
  MAX_CHARS = 2_000
  DAILY_CAP = 10
  WINDOW = 30.days

  belongs_to :assistant_token

  validates :asked, :needed, presence: true, length: { maximum: MAX_CHARS }
  validates :expected, length: { maximum: MAX_CHARS }, allow_nil: true
  validates :context_tool, :last_error, length: { maximum: 200 }, allow_nil: true

  def self.digest_for(needed) = Digest::SHA256.hexdigest(needed.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip)

  # The same vocabulary BugReport#reporter uses, so both maintainer screens name
  # a filer the same way. No user case: only assistants file these.
  def reporter
    return "anonymous assistant" if assistant_token.nil? || assistant_token.anonymous?

    assistant_token.software.to_h["agent_name"] || "named assistant"
  rescue StandardError
    "unknown"
  end

  # Returns [row, created, clipped]: `clipped` names the fields that were too
  # long, so a filer is told rather than discovering later that the end of its
  # proposal is missing.
  def self.record!(token:, asked:, needed:, expected: nil, context_tool: nil, last_error: nil)
    raise Ledger::Rejected.new([ { code: "RATE_LIMITED", path: "$", detail: "at most #{DAILY_CAP} feature requests a day for one assistant" } ]) if where(assistant_token: token).where("created_at >= ?", Time.current.beginning_of_day).count >= DAILY_CAP

    digest = digest_for(needed)
    if (existing = where(digest: digest).where("created_at >= ?", WINDOW.ago).order(:created_at).first)
      existing.update!(count: existing.count + 1)
      return [ existing, false, [] ]
    end
    clipped = { "asked" => asked, "needed" => needed, "expected" => expected }
              .select { |_, v| v.to_s.strip.length > MAX_CHARS }.keys
    [ create!(id: SecureRandom.uuid_v7, assistant_token: token, asked: asked.to_s.strip[0, MAX_CHARS], needed: needed.to_s.strip[0, MAX_CHARS],
              expected: expected.presence&.strip&.[](0, MAX_CHARS), context_tool: context_tool.presence&.[](0, 200), last_error: last_error.presence&.[](0, 200),
              anonymous: token.anonymous?, digest: digest).tap { |r| ContentReview.enqueue!(r) }, true, clipped ]
  end
end
