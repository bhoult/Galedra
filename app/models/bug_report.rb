# Something that went wrong, in the reporter's own words: an assistant through
# report_bug, or a person through /bug_reports/new (owner request, 2026-09-19).
# The sibling of FeatureRequest: outside the log, untrusted text, shown only to
# admins and moderators, never to other assistants or the public. Repeats of
# the same report within a month are counted, not duplicated.
class BugReport < ApplicationRecord
  include Triageable
  include FilingCap
  MAX_CHARS = 2_000
  WINDOW = 30.days

  belongs_to :assistant_token, optional: true
  belongs_to :user, optional: true

  validates :happened, presence: true, length: { maximum: MAX_CHARS }
  validates :expected, :steps, length: { maximum: MAX_CHARS }, allow_nil: true
  validates :url, :context_tool, :last_error, length: { maximum: 500 }, allow_nil: true
  # A cause is a separate claim from an observation, and a filer who has to say
  # how sure they are, and what they checked that did not explain it, files
  # fewer confident fictions (01a0c05d-db76).
  CONFIDENCE = %w[certain likely guess].freeze
  validates :suspected_cause, :ruled_out, length: { maximum: MAX_CHARS }, allow_nil: true
  validates :confidence, inclusion: { in: CONFIDENCE }, allow_nil: true

  def self.digest_for(happened) = Digest::SHA256.hexdigest(happened.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip)

  # Returns [report, created]. token or user says who reported; both nil is a visitor.
  def self.record!(happened:, token: nil, user: nil, expected: nil, steps: nil, url: nil, context_tool: nil, last_error: nil,
                   suspected_cause: nil, ruled_out: nil, confidence: nil)
    refuse_if_over_cap!(token, "bug reports")

    digest = digest_for(happened)
    if (existing = where(digest: digest).where("created_at >= ?", WINDOW.ago).order(:created_at).first)
      existing.update!(count: existing.count + 1)
      return [ existing, false, [] ]
    end
    # Clipping happens; being clipped in silence is the defect. `clipped` names
    # the fields that were too long so the filer is told at the time
    # (docs/experiments/2026-09-20-second-connector-run.md).
    clipped = { "happened" => happened, "expected" => expected, "steps" => steps,
                "suspected_cause" => suspected_cause, "ruled_out" => ruled_out }
              .select { |_, v| v.to_s.strip.length > MAX_CHARS }.keys
    clip = ->(s, n) { s.presence && s.to_s.strip[0, n] }
    [ create!(id: SecureRandom.uuid_v7, assistant_token: token, user: user, happened: happened.to_s.strip[0, MAX_CHARS],
              expected: clip.call(expected, MAX_CHARS), steps: clip.call(steps, MAX_CHARS), url: clip.call(url, 500),
              context_tool: clip.call(context_tool, 500), last_error: clip.call(last_error, 500),
              suspected_cause: clip.call(suspected_cause, MAX_CHARS), ruled_out: clip.call(ruled_out, MAX_CHARS),
              confidence: CONFIDENCE.include?(confidence.to_s) ? confidence.to_s : nil,
              anonymous: token ? token.anonymous? : user.nil?, digest: digest).tap { |r| ContentReview.enqueue!(r) }, true, clipped ]
  end

  def reporter
    return user.email_address if user
    return "anonymous assistant" if assistant_token&.anonymous?
    return assistant_token.software["agent_name"] || "named assistant" if assistant_token

    "visitor"
  rescue StandardError
    "named assistant"
  end
end
