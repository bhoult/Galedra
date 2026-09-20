require "rails_helper"

# Graph::Presenter.claim cost about 37 statements a claim, and the claims index
# renders a page of them (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md,
# finding 5, quantified). It is bounded by page size rather than corpus size,
# which is why it waited. This measures it rather than asserting it is fine.
RSpec.describe Graph::Presenter do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  def statements
    seen = []
    counter = ->(*, payload) { seen << payload[:name].to_s unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    seen
  end

  it "renders a claim in a bounded number of statements, and the same JSON as before" do
    author, = register_key
    source = create_source(author, content: "Survey: 62% of 400 respondents reported higher productivity.")
    location = create_location(author, source)
    claim = create_claim(author, "62% of respondents reported higher productivity.", type: "QUANTITATIVE")
    %w[SUPPORT CONTRADICT QUALIFY NEUTRAL].each_with_index do |direction, i|
      link_evidence(author, create_evidence(author, location, statement: "Passage #{i}."), claim, direction: direction)
    end
    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model

    Scoring::Score.call(claim, seq, model) # warm the score cache; this measures presentation
    rendered = described_class.claim(claim, seq, model: model)

    # The counts are what changed: four directions, the total and the pending
    # count came from six statements and now come from two.
    expect(rendered[:evidence_counts]).to eq(
      support: 1, contradict: 1, qualify: 1, neutral: 1, counted: 4, pending: 0
    )

    # Measured on this fixture, fresh instance throughout: 40 before any of this,
    # 35 after the edge memo and the retrieval batching, 32 after the counted
    # set was loaded once and the effective set derived from it, 30 once
    # Cards::Plain read its edges from the memo too.
    # The bound is a ratchet, not a target: it is still too many, and what is
    # left is named in the profiler entry rather than guessed at here. The four
    # remaining ClaimEdge loads are two from this memo and two from Cards::Plain,
    # whose filtered queries carry no explicit order and whose precedence is a
    # standing open question, so they were left alone deliberately.
    #
    # A FRESH instance, because Claim memoises its counted edges per object, so
    # rendering the same object twice measures a warm memo rather than a request.
    # The first version of this spec did exactly that and reported a saving twice
    # the real one.
    fresh = Claim.find(claim.id)
    seen = statements { described_class.claim(fresh, seq, model: model) }
    # 31 rather than 30 since Cards::Plain began checking that a sentence it
    # offers for repetition has its figures in the passage it rests on: one
    # SourceLocation load, and only for a candidate that carries a figure at all
    # (01a0c0ec). Raised deliberately and with the reason, because a budget that
    # creeps without one stops being a budget.
    expect(seen.size).to be <= 31, "#{seen.size} statements: #{seen.tally.sort_by { |_, v| -v }.first(8).inspect}"
  end
end
