require "rails_helper"

RSpec.describe "Content review of free text by consensus (owner request, 2026-09-19)", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:author) { User.create!(email_address: "author@example.com", password: password) }
  let(:author_token) { Assistants::Connect.call(user: author, name: "Author's", provider: "anthropic").last }
  let(:reviewer_a) { Assistants::Connect.call(user: User.create!(email_address: "a@example.com", password: password), name: "A", provider: "anthropic").last }
  let(:reviewer_b) { Assistants::Connect.call(user: User.create!(email_address: "b@example.com", password: password), name: "B", provider: "openai").last }
  let(:anon) { Assistants::Connect.call(user: nil, name: "Anon", provider: "other").last }

  def call_tool(name, arguments, tok)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
    body = response.parsed_body
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  it "queues every new piece of free text and settles it by two agreeing principals, never the author" do
    claim = create_claim(register_key.first, "Remote work raises productivity.", type: "CAUSAL")
    BugReport.record!(happened: "The page broke", expected: "a page")
    FeatureRequest.record!(token: AssistantToken.find_by_token(author_token), asked: "list by source", needed: "a filter")
    PersonalAssessment.set!(user: author, claim: claim, stance: "AGREE", rationale: "you absolute [slur], obviously")
    AffiliationRequest.file!(user: author, text: "Quaker")
    expect(ContentReview.pending.count).to eq(6)
    expect(ContentReview.pending.pluck(:subject_type).uniq).to match_array(%w[BugReport FeatureRequest PersonalAssessment AffiliationRequest])

    data, err = call_tool("next_content_review", {}, anon)
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("NOT_AUTHORIZED")
    data, = call_tool("list_tasks", {}, reviewer_a)
    expect(data["content_reviews_pending"]).to eq(6)

    # The author's own assistant is never offered its own words.
    mine, = call_tool("next_content_review", {}, author_token)
    expect(mine["kind"]).to eq("bug report")
    feature = ContentReview.pending.find_by(subject_type: "FeatureRequest", field: "asked")
    data, err = call_tool("submit_content_review", { review_id: feature.id, outcome: "CLEAN" }, author_token)
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("NOT_AUTHORIZED")

    first, err = call_tool("next_content_review", {}, reviewer_a)
    expect(err).to be(false), first.inspect
    expect(first).to include("available" => true, "kind" => "bug report", "field" => "happened", "untrusted_text" => "The page broke")
    expect(first["rules"]).to include("Disagreement")
    data, = call_tool("submit_content_review", { review_id: first["review_id"], outcome: "CLEAN" }, reviewer_a)
    expect(data["status"]).to eq("PENDING")
    expect(data["consensus"]).to include("verdicts" => 1, "needed" => 2)
    data, err = call_tool("submit_content_review", { review_id: first["review_id"], outcome: "CLEAN" }, reviewer_a)
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("DUPLICATE")
    again, = call_tool("next_content_review", {}, reviewer_a)
    expect(again["review_id"]).not_to eq(first["review_id"])
    data, = call_tool("submit_content_review", { review_id: first["review_id"], outcome: "CLEAN" }, reviewer_b)
    expect(data["status"]).to eq("CLEAN")

    slur = ContentReview.pending.find_by(subject_type: "PersonalAssessment")
    call_tool("submit_content_review", { review_id: slur.id, outcome: "OFFENSIVE", reason: "slur" }, reviewer_a)
    expect(slur.reload.status).to eq("PENDING")
    expect(author.personal_assessments.first.reload.rationale).to eq("you absolute [slur], obviously")
    call_tool("submit_content_review", { review_id: slur.id, outcome: "CLEAN" }, reviewer_b)
    expect(slur.reload.status).to eq("PENDING")
    reviewer_c = Assistants::Connect.call(user: User.create!(email_address: "c@example.com", password: password), name: "C", provider: "xai").last
    data, = call_tool("submit_content_review", { review_id: slur.id, outcome: "OFFENSIVE", reason: "slur" }, reviewer_c)
    expect(data["status"]).to eq("REDACTED")
    expect(author.personal_assessments.first.reload.rationale).to eq(ContentReview::REDACTED_TEXT)
    expect(slur.reload).to have_attributes(status: "REDACTED", original_text: "you absolute [slur], obviously")
    data, = call_tool("submit_content_review", { review_id: slur.id, outcome: "MAYBE" }, reviewer_b)
    expect(data["errors"].first["code"]).to eq("SCHEMA_INVALID")

    post "/session", params: { email_address: author.email_address, password: password }
    get "/admin/content_reviews"
    expect(response).to redirect_to(root_path)
    author.update!(admin: true)
    get "/admin/content_reviews"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("you absolute [slur], obviously").and include("Quaker")
    post "/admin/content_reviews/#{slur.id}/restore"
    expect(author.personal_assessments.first.reload.rationale).to eq("you absolute [slur], obviously")
    expect(slur.reload.status).to eq("CLEAN")
  end

  it "settles a lone, uncontradicted verdict after two days and never queues empty text" do
    r = BugReport.record!(happened: "x").first
    item = ContentReview.pending.find_by(subject_type: "BugReport", subject_id: r.id)
    expect(ContentReview.where(subject_type: "BugReport", field: "expected").count).to eq(0)
    item.vote!(AssistantToken.find_by_token(reviewer_a), "OFFENSIVE", reason: "test")
    expect(item.reload.status).to eq("PENDING")
    SettleLoneVerdictsJob.perform_now
    expect(item.reload.status).to eq("PENDING")
    ReviewVerdict.update_all(created_at: 3.days.ago)
    SettleLoneVerdictsJob.perform_now
    expect(item.reload.status).to eq("REDACTED")
    expect(r.reload.happened).to eq(ContentReview::REDACTED_TEXT)
  end
end
