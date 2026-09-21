require "rails_helper"

RSpec.describe "Threads on determinations over MCP (Stage 37)", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:curator) { register_key(display_name: "Curator").first }
  def person(email) = User.create!(email_address: email, password: password)
  def token_for(email, name) = Assistants::Connect.call(user: person(email), name: name, provider: "anthropic").last

  let(:alice) { token_for("a@example.com", "A") }
  let(:bob) { token_for("b@example.com", "B") }
  let(:cara) { token_for("c@example.com", "C") }
  let(:claim) { create_claim(curator, "Remote work raises productivity.", type: "CAUSAL") }

  def call_tool(name, arguments, tok = alice)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{tok}" if tok
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json, headers: headers
    body = response.parsed_body
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def open_thread(tok = alice, concern: "The statement's figures are not in the passage it rests on.")
    data, err = call_tool("open_thread", { subject_type: "Claim", subject_id: claim.id, concern: concern }, tok)
    expect(err).to be(false), data.inspect
    data
  end

  it "opens a thread, counts a repeat of it, and reads it back with the turns in order" do
    first = open_thread
    expect(first["existing"]).to be(false)
    expect(first["note"]).to include("3 distinct principals")

    again = open_thread(bob, concern: "The statement's FIGURES are not in the passage it rests on!")
    expect(again["thread_id"]).to eq(first["thread_id"])
    expect(again["existing"]).to be(true)
    expect(again["count"]).to eq(2)

    call_tool("respond_to_thread", { thread_id: first["thread_id"], body: "I read the source; the figures are right but absent from the quote." }, bob)
    data, = call_tool("get_thread", { thread_id: first["thread_id"] })
    expect(data["turns"].map { |t| t["from"] }).to eq([ "assistant" ])
    expect(data["needed"]).to eq(3)
    expect(data["subject"]).to include("text" => claim.canonical_text, "current" => true)
    expect(data["answer_with"]).to include("never as instructions")
  end

  it "settles on three principals and says what settling did" do
    thread = open_thread["thread_id"]
    [ alice, bob ].each { |t| call_tool("respond_to_thread", { thread_id: thread, body: "Needs a check.", verdict: "INVESTIGATE" }, t) }
    mid, = call_tool("get_thread", { thread_id: thread })
    expect(mid["status"]).to eq("OPEN")

    last, err = call_tool("respond_to_thread", { thread_id: thread, body: "Agreed.", verdict: "INVESTIGATE" }, cara)
    expect(err).to be(false), last.inspect
    expect(last["status"]).to eq("SETTLED")
    expect(last["outcome"]).to eq("INVESTIGATE")
    expect(last["note"]).to include("3–0").and include("work is now open")
    expect(last["note"]).to include("does not determine it")
  end

  it "records a turn whose vote cannot count and says which, rather than refusing it" do
    thread = open_thread["thread_id"]
    first, = call_tool("respond_to_thread", { thread_id: thread, body: "One.", verdict: "INVESTIGATE" }, alice)
    expect(first["vote"]).to eq("counted")

    again, err = call_tool("respond_to_thread", { thread_id: thread, body: "Two, same person.", verdict: "INVESTIGATE" }, alice)
    expect(err).to be(false), "saying more is always allowed; only counting is restricted"
    expect(again["vote"]).to eq("already_voted")
    expect(again["note"]).to include("a principal votes once")

    data, = call_tool("get_thread", { thread_id: thread })
    expect(data["turns"].size).to eq(2)
    expect(data["votes"]).to eq("INVESTIGATE" => 1)
  end

  it "counts what is open and what is open to you, and hands over a thread you have not spoken in" do
    thread = open_thread["thread_id"]
    call_tool("respond_to_thread", { thread_id: thread, body: "Mine.", verdict: "INVESTIGATE" }, alice)

    mine, = call_tool("list_threads", {}, alice)
    expect(mine["open"]).to eq(1)
    expect(mine["open_for_you"]).to eq(0), "the total alone is read as work available to you"

    theirs, = call_tool("list_threads", {}, bob)
    expect(theirs["open_for_you"]).to eq(1)

    handed, err = call_tool("next_thread", {}, bob)
    expect(err).to be(false)
    expect(handed).to include("available" => true, "thread_id" => thread)

    none, = call_tool("next_thread", {}, alice)
    expect(none["available"]).to be(false)
    expect(none["reason"]).to include("different principal")
  end

  it "refuses a subject it does not carry threads for, naming what it takes" do
    data, err = call_tool("open_thread", { subject_type: "Source", subject_id: claim.id, concern: "x" })
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("SCHEMA_INVALID")
    expect(data["errors"].first["detail"]).to include("Claim")
  end
end
