require "rails_helper"

RSpec.describe DeterminationThread do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:curator) { register_key(display_name: "Curator").first }
  let(:model) { Scoring::Registry.default_model }

  def person(email) = User.create!(email_address: email, password: password)
  def assistant(user, name) = AssistantToken.find_by_token(Assistants::Connect.call(user: user, name: name, provider: "anthropic").last)

  let(:alice) { assistant(person("a@example.com"), "A") }
  let(:bob) { assistant(person("b@example.com"), "B") }
  let(:cara) { assistant(person("c@example.com"), "C") }

  let(:claim) { create_claim(curator, "Remote work raises productivity.", type: "CAUSAL") }
  let(:thread) { described_class.record!(subject: claim, concern: "The statement's figures are not in the passage it rests on.").first }

  def vote(thread, token, verdict, body: "A turn.") = thread.respond!(body: body, token: token, verdict: verdict)

  it "settles on three principals naming the same outcome, and not on two" do
    vote(thread, alice, "NO_FURTHER_WORK")
    vote(thread, bob, "NO_FURTHER_WORK")
    expect(thread.reload).to be_open, "two agreeing is not three"
    vote(thread, cara, "NO_FURTHER_WORK")
    expect(thread.reload).to be_settled
    expect(thread.outcome).to eq("NO_FURTHER_WORK")
    expect(thread.split).to eq([ 3, 0 ])
  end

  # The shape a node like this one actually has: one person, many sessions.
  # Agreement has to be between people, not between sessions (Invariant 9).
  it "does not settle on three tokens of one principal" do
    one = person("one@example.com")
    3.times.map { |i| assistant(one, "Session #{i}") }.each { |t| vote(thread, t, "INVESTIGATE") }
    expect(thread.reload).to be_open
    expect(thread.tally).to eq("INVESTIGATE" => 1), "eleven tokens under one principal settle nothing"
    expect(thread.turns.count).to eq(3), "but every turn is still recorded"
  end

  it "leaves a two-two split open rather than letting whoever spoke last win" do
    vote(thread, alice, "NO_FURTHER_WORK")
    vote(thread, bob, "NO_FURTHER_WORK")
    vote(thread, cara, "INVESTIGATE")
    vote(thread, assistant(person("d@example.com"), "D"), "INVESTIGATE")
    expect(thread.reload).to be_open, "a majority is not agreement"
    expect(thread.tally).to eq("NO_FURTHER_WORK" => 2, "INVESTIGATE" => 2)

    # The owner's sequence: closed, closed, opened, opened, closed.
    vote(thread, assistant(person("e@example.com"), "E"), "NO_FURTHER_WORK")
    expect(thread.reload).to be_settled
    expect(thread.outcome).to eq("NO_FURTHER_WORK")
    expect(thread.split).to eq([ 3, 2 ])
    expect(thread.state_line).to include("3–2")
  end

  # A person writing directly and that person's assistant writing on their
  # behalf are the same principal. Without this the three-principal guard has a
  # hole you could drive a session through.
  it "counts a person and that person's own assistant as one principal" do
    dave = person("dave@example.com")
    thread.respond!(body: "I think this needs checking.", user: dave, verdict: "INVESTIGATE")
    thread.respond!(body: "Agreeing with myself through my assistant.", token: assistant(dave, "Dave's"), verdict: "INVESTIGATE")
    expect(thread.reload.tally).to eq("INVESTIGATE" => 1)
    vote(thread, alice, "INVESTIGATE")
    expect(thread.reload).to be_open, "that is two principals, not three"
  end

  it "records a turn whose vote cannot count, and says which" do
    expect(vote(thread, alice, "INVESTIGATE")).to include(vote: :counted)
    expect(vote(thread, alice, "INVESTIGATE")).to include(vote: :already_voted)
    anon = AssistantToken.find_by_token(Assistants::Connect.call(user: nil, name: "Anon", provider: "other").last)
    expect(vote(thread, anon, "INVESTIGATE")).to include(vote: :unattributable)
    expect(thread.reload.turns.count).to eq(3), "saying more is always allowed; only counting is restricted"
    expect(thread.tally).to eq("INVESTIGATE" => 1)
  end

  # Silence is not a conclusion. The register's timeout closes a report, which
  # reads as agreement when it is really an absence; a thread retires instead.
  it "retires on silence, leaves the work list, and revives on a turn with its votes intact" do
    vote(thread, alice, "INVESTIGATE")
    thread.update!(last_turn_at: described_class::RETIRE_AFTER.ago - 1.day)
    described_class.retire_silent!
    expect(thread.reload).to be_retired
    expect(thread).not_to be_workable
    expect(thread.state_line).to include("Nothing was agreed")

    thread.respond!(body: "Still think this matters.", token: bob)
    expect(thread.reload).to be_open
    expect(thread.tally).to eq("INVESTIGATE" => 1), "reviving keeps what it had"
  end

  it "collapses the same concern onto one thread, counting it, including after it settles" do
    thread
    again, = described_class.record!(subject: claim, concern: "The statement's FIGURES are not in the passage it rests on!")
    expect(again.id).to eq(thread.id)
    expect(again.count).to eq(2)

    [ alice, bob, cara ].each { |t| vote(thread, t, "NO_FURTHER_WORK") }
    third, = described_class.record!(subject: claim, concern: "The statement's figures are not in the passage it rests on.")
    expect(third.id).to eq(thread.id), "re-filing must not become the endless argument the settlement rule ends"
    expect(third.count).to eq(3)
  end

  # The scope exists because the header badge counts these on every page render,
  # including the signed-out home page, and walking every thread to query its
  # subject is 1 + N there. The two readings have to agree.
  it "counts workable threads in SQL the same way the predicate does one at a time" do
    thread
    other = create_claim(curator, "A second claim.", type: "CAUSAL")
    described_class.record!(subject: other, concern: "Another concern entirely, about this one.")
    expect(described_class.workable.count).to eq(described_class.open_threads.to_a.count(&:workable?))

    append(action_type: "MERGE_CLAIMS", key_pair: curator,
           payload: { "from_claim_id" => other.id, "into_claim_id" => claim.id, "reason" => "same proposition" })
    expect(described_class.workable.count).to eq(1)
    expect(described_class.workable.count).to eq(described_class.open_threads.to_a.count(&:workable?))
  end

  it "stays as history when its subject stops being current, and stops being work" do
    vote(thread, alice, "INVESTIGATE")
    other = create_claim(curator, "A claim to merge into.", type: "CAUSAL")
    append(action_type: "MERGE_CLAIMS", key_pair: curator,
           payload: { "from_claim_id" => claim.id, "into_claim_id" => other.id, "reason" => "same proposition" })
    expect(thread.reload).to be_open
    expect(thread).not_to be_workable
    expect(thread.state_line).to include("no longer current")
    expect(thread.turns.count).to be_positive, "history is kept, not cancelled"
  end
end
