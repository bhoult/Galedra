require "rails_helper"

RSpec.describe Threads::Settle do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:curator) { register_key(display_name: "Curator").first }
  let(:model) { Scoring::Registry.default_model }

  def person(email) = User.create!(email_address: email, password: password)
  def assistant(email, name) = AssistantToken.find_by_token(Assistants::Connect.call(user: person(email), name: name, provider: "anthropic").last)
  def vote(thread, token, verdict) = thread.respond!(body: "A turn.", token: token, verdict: verdict)

  let(:claim) { create_claim(curator, "Remote work raises productivity.", type: "CAUSAL") }
  let(:thread) { DeterminationThread.record!(subject: claim, concern: "The figures are not in the passage.").first }
  let(:voters) { %w[a b c d e].map { |x| assistant("#{x}@example.com", x.upcase) } }

  def score(seq) = Scoring::Score.call(claim.reload, seq, model)

  # The acceptance this whole stage exists to satisfy: at a given seq, byte for
  # byte, either side of a settlement. Held at one seq deliberately — connecting
  # the voters registers their keys, which moves the head, and comparing across
  # two heads would measure the test's own setup rather than the thread.
  it "changes nothing the scorer reads, under either outcome" do
    location = create_location(curator, create_source(curator, content: "Output rose in the trial. #{'word ' * 20}"), start: 0, finish: 25)
    link_evidence(curator, create_evidence(curator, location, statement: "Output rose in the trial."), claim)
    Tasks::OpenVerification.call([ claim ])
    voters && thread
    seq = Contribution.maximum(:seq)
    before = score(seq)
    snapshot = [ before.assessment_state, before.probability, before.trace ]

    voters.first(3).each { |t| vote(thread, t, "NO_FURTHER_WORK") }
    expect(thread.reload).to be_settled
    after = score(seq)
    expect([ after.assessment_state, after.probability, after.trace ]).to eq(snapshot),
                                                                         "a thread guides evidence gathering; it does not determine it"

    other = DeterminationThread.record!(subject: claim, concern: "A second and different concern about this claim entirely.").first
    voters.first(3).each { |t| other.respond!(body: "Check it.", token: t, verdict: "INVESTIGATE") }
    expect(other.reload.outcome).to eq("INVESTIGATE")
    expect([ score(seq).assessment_state, score(seq).probability, score(seq).trace ]).to eq(snapshot), "and the same the other way"
  end

  it "cancels only the open, unleased tasks when it stands work down" do
    Tasks::OpenVerification.call([ claim ])
    leased = Task.where(target_id: claim.id).first
    Tasks::Lease.next(contributor: voters.first.agent, delegation: voters.first.delegation, target_id: claim.id)
    live = Task.where(target_id: claim.id).select { |t| t.open_slots < t.required_assignments }

    voters.first(3).each { |t| vote(thread, t, "NO_FURTHER_WORK") }
    cancelled = Task.where(target_id: claim.id, status: "CANCELLED")
    expect(cancelled).to be_any
    expect(cancelled.map(&:cancelled_reason).uniq).to eq([ described_class::CANCELLED_BY_THREAD ])
    live.each { |t| expect(t.reload.status).not_to eq("CANCELLED"), "a worker mid-lease is not overruled by a conversation it was not in" }
  end

  # The owner's sequence: closed, closed, opened, opened, closed. Three principals
  # settle it and the argument ends there, but the concern the minority named
  # gets a check rather than another round of argument.
  it "opens one task carrying the dissent when it stands work down over disagreement" do
    Tasks::OpenVerification.call([ claim ])
    vote(thread, voters[0], "NO_FURTHER_WORK")
    vote(thread, voters[1], "NO_FURTHER_WORK")
    thread.respond!(body: "The figures are wrong, not merely unquoted.", token: voters[2], verdict: "INVESTIGATE")
    thread.respond!(body: "Agreed with the above; this wants a source.", token: voters[3], verdict: "INVESTIGATE")
    expect(thread.reload).to be_open

    expect { vote(thread, voters[4], "NO_FURTHER_WORK") }
      .to change { Task.where(target_id: claim.id, status: "OPEN").count }
    expect(thread.reload.split).to eq([ 3, 2 ])

    opened = Task.where(target_id: claim.id, status: "OPEN").order(:created_at).last
    dissent = opened.packet.dig("context", "from_thread")
    expect(dissent["thread_id"]).to eq(thread.id)
    expect(dissent["settled_as"]).to eq("NO_FURTHER_WORK")
    expect(dissent["untrusted_dissent"]).to include("The figures are wrong, not merely unquoted.")
    expect(opened.packet_hash).to eq(Tasks::Packet.hash(opened.packet)), "the context travels inside the signed packet"
  end

  it "opens nothing extra when the settlement was unopposed" do
    Tasks::OpenVerification.call([ claim ])
    voters.first(3).each { |t| vote(thread, t, "NO_FURTHER_WORK") }
    expect(Task.where(target_id: claim.id, status: "OPEN")).to be_empty, "the task is the dissent's, not a reflex"
  end

  # Durability rests on an incidental property of Tasks::OpenVerification: its
  # existence check ignores status, so a CANCELLED row blocks re-creation.
  # Narrowing that check would look like a tidy-up and would quietly make every
  # settlement temporary.
  it "stays cancelled when the verification path runs again" do
    Tasks::OpenVerification.call([ claim ])
    voters.first(3).each { |t| vote(thread, t, "NO_FURTHER_WORK") }
    expect { Tasks::OpenVerification.call([ claim ]) }.not_to change { Task.where(target_id: claim.id, status: "OPEN").count }
  end

  it "opens work when it settles the other way" do
    voters.first(3).each { |t| vote(thread, t, "INVESTIGATE") }
    expect(thread.reload.outcome).to eq("INVESTIGATE")
    expect(Task.where(target_id: claim.id, status: "OPEN")).to be_any
    expect(EvidenceClaimLink.count).to eq(0), "raising a check is not recording evidence"
  end
end
