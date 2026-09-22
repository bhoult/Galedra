require "rails_helper"

# Stage 40. The Rails log records a duration and not a statement count, so the
# three slow paths found on 2026-09-21 were invisible in it. What is recorded
# here is the count, the call count, and nothing about who asked.
RSpec.describe "Recording what the node was asked for", type: :request do
  include GraphHelpers

  def with_metrics(value)
    was = ENV.fetch(RequestMetrics::ENV_KEY, nil)
    ENV[RequestMetrics::ENV_KEY] = value
    yield
  ensure
    was.nil? ? ENV.delete(RequestMetrics::ENV_KEY) : ENV[RequestMetrics::ENV_KEY] = was
  end

  it "records nothing at all when the flag is off" do
    with_metrics("off") do
      get "/claims"
      expect(response).to have_http_status(:ok)
    end

    expect(RequestTally.count).to eq(0)
    expect(RequestSample.count).to eq(0)
  end

  it "counts every call, and keeps the slow ones in full" do
    pair, = register_key
    claim = create_claim(pair, "A claim to look at more than once.")

    with_metrics("on") do
      3.times { get "/claims" }
      get "/claims/#{claim.id}"
    end

    index = RequestTally.find_by(action: "claims#index")
    expect(index.calls).to eq(3)
    expect(index.statements).to be_positive
    expect(index.total_ms).to be_positive
    expect(index.max_ms).to be <= index.total_ms
    expect(RequestTally.find_by(action: "claims#show").calls).to eq(1)

    # Nothing here was slow, so nothing was kept in full.
    expect(RequestSample.count).to eq(0)

    # One that is. The threshold is on either axis: a page that issues hundreds
    # of statements is worth keeping however quickly it answered, because that
    # is what an N+1 looks like before the corpus grows.
    stub_const("RequestMetrics::MANY_STATEMENTS", 1)
    with_metrics("on") { get "/claims" }

    sample = RequestSample.order(:recorded_at).last
    expect(sample.action).to eq("claims#index")
    expect(sample.method).to eq("GET")
    expect(sample.status).to eq(200)
    expect(sample.statements).to be_positive
    expect(sample.duration_ms).to be_positive
    # The corpus it was taken against, without which a timing is not evidence.
    expect(sample.head_seq).to eq(Contribution.maximum(:seq))
    expect(RequestTally.find_by(action: "claims#index").slow_calls).to eq(1)
  end

  it "records no address and no identity" do
    with_metrics("on") do
      stub_const("RequestMetrics::MANY_STATEMENTS", 1)
      get "/claims", headers: { "REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }
    end

    columns = RequestSample.column_names + RequestTally.column_names
    expect(columns.grep(/ip|address|remote|user|contributor|agent/i)).to eq([])
    expect(RequestSample.all.map(&:attributes).to_json).not_to include("203.0.113.9")
  end

  it "counts the statements the request really issued" do
    pair, = register_key
    create_claim(pair, "Something for the index to list.")

    counted = 0
    counter = ->(*, payload) { counted += 1 unless payload[:name].to_s == "SCHEMA" || payload[:cached] }
    with_metrics("on") do
      stub_const("RequestMetrics::MANY_STATEMENTS", 1)
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get "/claims" }
    end

    sample = RequestSample.find_by(action: "claims#index")
    # The independent count includes the metrics' own writes — the tally upsert,
    # the sample insert, the head-seq read and their transactions — which happen
    # after the recorded count is taken, so it is the same or a handful higher.
    expect(sample.statements).to be_positive
    expect(sample.statements).to be <= counted
    expect(counted - sample.statements).to be <= 8, "the recorder should account for all but its own writes"
  end

  # Stage 41: every MCP tool arrives at one controller action, so `mcp#create`
  # averaged list_claims with record_investigation and neither could be blamed
  # for the 259 statements a call it recorded on 2026-09-22.
  it "files an MCP call under the tool that was called, not the action they share" do
    plaintext = Assistants::Connect.call(user: User.create!(email_address: "tool@example.com", password: "correct horse battery staple"),
                                         name: "Worker", provider: "other").last

    with_metrics("on") do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                             params: { name: "list_topics", arguments: {} } }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{plaintext}" }
    end

    expect(response).to have_http_status(:ok)
    expect(RequestTally.pluck(:action)).to eq([ "mcp#list_topics" ])
    expect(RequestTally.pluck(:action)).not_to include("mcp#create")
  end

  describe "retention" do
    before do
      RequestTally.create!(id: SecureRandom.uuid_v7, action: "claims#show", hour: 40.days.ago.beginning_of_hour,
                           calls: 5, statements: 10, slow_calls: 0, total_ms: 100, max_ms: 30,
                           created_at: 40.days.ago, updated_at: 40.days.ago)
      RequestTally.create!(id: SecureRandom.uuid_v7, action: "claims#show", hour: 1.hour.ago.beginning_of_hour,
                           calls: 2, statements: 4, slow_calls: 0, total_ms: 40, max_ms: 25,
                           created_at: 1.hour.ago, updated_at: 1.hour.ago)
      RequestSample.create!(id: SecureRandom.uuid_v7, action: "sections#show", method: "GET", status: 200,
                           duration_ms: 3000, statements: 5343, recorded_at: 40.days.ago)
      RequestSample.create!(id: SecureRandom.uuid_v7, action: "claims#show", method: "GET", status: 200,
                           duration_ms: 900, statements: 120, recorded_at: 1.hour.ago)
    end

    it "drops what is older than the window and nothing newer" do
      result = RequestMetrics::Prune.call(keep_days: 30)

      expect(result[:tallies]).to eq(1)
      expect(result[:samples]).to eq(1)
      expect(RequestTally.count).to eq(1)
      expect(RequestSample.pluck(:action)).to eq([ "claims#show" ])
    end

    # The point of this one: after a fix, the old rows stop being evidence and
    # start being a lie about where the time goes.
    it "drops one action's rows once it has been fixed, and leaves the rest" do
      result = RequestMetrics::Prune.clear("sections#show")

      expect(result[:samples]).to eq(1)
      expect(RequestSample.pluck(:action)).to eq([ "claims#show" ])
      expect(RequestTally.count).to eq(2)
    end
  end
end
