require "rails_helper"

# Stage 46: the atomic breakdown comes from an assistant or a person, not a
# sentence splitter. Analyze text stores the text and opens extraction tasks.
RSpec.describe "The atomic breakdown comes from an assistant (Stage 46)", type: :request do
  before { release_models }

  let(:password) { "correct horse battery staple" }

  def sign_up(email)
    post "/users", params: { user: { email_address: email, password: password, password_confirmation: password } }
    User.find_by!(email_address: email)
  end

  def call_tool(name, arguments, tok)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
    [ response.parsed_body.dig("result", "structuredContent"), response.parsed_body.dig("result", "isError") ]
  end

  # The five statements the splitter was measured on (the stage file's evidence).
  STATEMENTS = [
    "The new law, passed in 2023, cut violent crime by 40% and saved taxpayers $2 billion, according to the mayor.",
    "Einstein failed math in school and later won the Nobel Prize for relativity.",
    "Vaccines cause autism, which is why rates rose after the MMR shot was introduced in 1971 and doctors won't admit it.",
    "Dr. Smith of the U.S. Dept. of Energy said the plant is safe. It isn't.",
    "Coffee is good for you: a 2019 Harvard study of 500,000 people (Lee et al., 2019) found drinkers live longer."
  ].freeze

  it "records five sources and opens five extraction tasks from five pastes, and creates no claim (acceptance 1)" do
    sign_up("paster@example.com")
    STATEMENTS.each_with_index { |text, i| post "/analyze", params: { title: "Statement #{i + 1}", text: text } }
    expect(Source.where("title LIKE 'Statement %'").count).to eq(5)
    tasks = Task.where(task_type: "CLAIM_EXTRACTION", target_type: "SOURCE", status: "OPEN")
    expect(tasks.count).to eq(5)
    expect(tasks.map(&:target_id).uniq.size).to eq(5)
    expect(Claim.count).to eq(0)
    # The packet carries the whole statement, untrusted and unsplit.
    abbreviations = tasks.find { |t| Source.find(t.target_id).title == "Statement 4" }
    expect(abbreviations.packet.dig("context", "excerpts").map { |e| e["untrusted_excerpt"] }).to eq([ STATEMENTS[3] ])
  end

  it "lets a volunteer's assistant work the task, and its claims appear on the source's page (acceptance 2)" do
    sign_up("paster@example.com")
    post "/analyze", params: { title: "Mayor's statement", text: STATEMENTS[0] }
    source = Source.find_by!(title: "Mayor's statement")
    volunteer = Assistants::Connect.call(user: User.create!(email_address: "vol@example.com", password: password), name: "Volunteer", provider: "openai").last

    task, err = call_tool("next_task", { types: [ "CLAIM_EXTRACTION" ] }, volunteer)
    expect(err).to be(false), task.inspect
    expect(task["target"]["source_id"]).to eq(source.id)
    claims = [ { handle: "a", text: "A new law was passed in 2023.", type: "HISTORICAL" },
               { handle: "b", text: "The new law cut violent crime by 40%.", type: "CAUSAL" },
               { handle: "c", text: "The new law saved taxpayers $2 billion.", type: "QUANTITATIVE" },
               { handle: "d", text: "The mayor said the new law cut violent crime by 40% and saved taxpayers $2 billion.", type: "TEXTUAL" } ]
    data, err = call_tool("submit_task", { task_id: task["task_id"], outcome: "CLAIMS_FOUND", answer: { claims: claims } }, volunteer)
    expect(err).to be(false), data.inspect

    get "/sources/#{source.id}"
    expect(response.body).to include("4 claims checked")
    claims.each { |c| expect(response.body).to include(ERB::Util.html_escape(c[:text])) }
  end

  it "files the person's own assistant's check under the text and closes the extraction tasks" do
    user = sign_up("paster@example.com")
    post "/analyze", params: { title: "Einstein", text: STATEMENTS[1] }
    source = Source.find_by!(title: "Einstein")
    get "/sources/#{source.id}/analyze"
    expect(response.body).to include("source: &quot;#{source.id}&quot;")

    own = Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last
    bundle = { "statement" => STATEMENTS[1], "on_duplicate" => "create",
               "claims" => [ { "handle" => "a", "text" => "Einstein failed mathematics in school.", "type" => "HISTORICAL", "source" => source.id,
                               "preliminary" => { "expectation" => "EXPECTED_NOT_TO_HOLD", "rationale" => "His school records show high marks in mathematics." } },
                             { "handle" => "b", "text" => "Einstein won the Nobel Prize in Physics for his theory of relativity.", "type" => "HISTORICAL", "source" => source.id,
                               "preliminary" => { "expectation" => "EXPECTED_NOT_TO_HOLD", "rationale" => "The 1921 prize cited the photoelectric effect." } } ] }
    data, err = call_tool("record_investigation", bundle, own)
    expect(err).to be(false), data.inspect
    expect(Claim.where(extracted_from_source_id: source.id).count).to eq(2)
    expect(Task.where(task_type: "CLAIM_EXTRACTION", target_id: source.id).pluck(:status, :cancelled_reason)).to eq([ [ "CANCELLED", "RECORDED_BY_REQUESTER" ] ])
    get "/sources/#{source.id}"
    expect(response.body).to include("2 claims checked")

    # Someone else's assistant filing under the text leaves its tasks alone.
    post "/session", params: { email_address: "paster@example.com", password: password }
    post "/analyze", params: { title: "Coffee", text: STATEMENTS[4] }
    coffee = Source.find_by!(title: "Coffee")
    stranger = Assistants::Connect.call(user: User.create!(email_address: "other@example.com", password: password), name: "Other", provider: "openai").last
    data, err = call_tool("record_investigation", { "on_duplicate" => "create", "claims" => [ { "handle" => "a", "text" => "Coffee drinkers live longer than non-drinkers.", "type" => "CAUSAL", "source" => coffee.id } ] }, stranger)
    expect(err).to be(false), data.inspect
    expect(Task.where(task_type: "CLAIM_EXTRACTION", target_id: coffee.id).pluck(:status)).to eq([ "OPEN" ])

    data, err = call_tool("record_investigation", { "claims" => [ { "handle" => "a", "attach_to" => Claim.last.id, "source" => coffee.id } ] }, stranger)
    expect(err).to be(true)
    expect(data["errors"].first).to include("path" => "$.claims[0].source")
  end

  it "keeps no function on the adapter without a caller, and nothing calls an extractor (acceptance 3)" do
    app = Dir[Rails.root.join("app/**/*.{rb,erb}")].reject { |f| f.end_with?("app/services/llm/adapter.rb") }.map { |f| File.read(f) }.join("\n")
    expect(app).not_to match(/\bextract_claims\b|Claims::Extract\b/)
    (Llm::Adapter.current.class.public_instance_methods(false) - [ :name ]).each do |method|
      expect(app).to match(/\.#{method}\b/), "#{Llm::Adapter.current.class}##{method} has no caller in app/"
    end
  end

  it "refuses a paste over the size rule, naming the outline route, and records nothing (acceptance 5)" do
    sign_up("paster@example.com")
    count = Contribution.count
    long = Array.new(Guidance::MAX_CHECK_WORDS + 1) { |i| "word#{i}" }.join(" ")
    post "/analyze", params: { title: "Too long", text: long }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("create_outline").and include("#{(Guidance::MAX_CHECK_WORDS + 1).to_fs(:delimited)} words")
    expect(Contribution.count).to eq(count)
    expect(Task.where(task_type: "CLAIM_EXTRACTION").count).to eq(0)
  end

  it "reads a long paste in windows a packet carries whole, one task each, covering every word" do
    sign_up("paster@example.com")
    paragraphs = Array.new(9) { |p| Array.new(120) { |w| "p#{p}w#{w}" }.join(" ") + "." }
    text = paragraphs.join("\n\n")
    expect(text.split.size).to be < Guidance::MAX_CHECK_WORDS
    expect(text.length).to be > Tasks::Types::EXCERPT_CAP * 2
    post "/analyze", params: { title: "Long memo", text: text }
    source = Source.find_by!(title: "Long memo")
    tasks = Task.where(task_type: "CLAIM_EXTRACTION", target_id: source.id).order(:created_at)
    expect(tasks.size).to be >= 3
    excerpts = tasks.map { |t| t.packet.dig("context", "excerpts").sole["untrusted_excerpt"] }
    expect(excerpts).to all(satisfy { |e| e.length <= Tasks::Types::EXCERPT_CAP })
    expect(excerpts.join(" ").split).to eq(text.split)
    expect(excerpts).to all(end_with("."))  # each window ends at a paragraph break
    tasks.each do |t|
      location = SourceLocation.find(t.packet.dig("context", "excerpts").sole["source_location_id"])
      expect(source.slice(location.locator["start"], location.locator["end"])).to eq(location.excerpt)
    end
  end

  it "records a hand-typed form whole or not at all" do
    sign_up("paster@example.com")
    post "/analyze", params: { title: "Memo", text: STATEMENTS[1] }
    source = Source.find_by!(title: "Memo")
    count = Contribution.count
    post "/sources/#{source.id}/claims", params: { claims: {
      "0" => { canonical_text: "Einstein failed mathematics in school.", claim_type: "HISTORICAL", affirms_not_private_individual: "1" },
      "1" => { canonical_text: "x" * (Claim::MAX_TEXT_CHARS + 1), claim_type: "HISTORICAL", affirms_not_private_individual: "1" } } }
    expect(flash[:alert]).to be_present
    expect(Contribution.count).to eq(count)
    expect(Task.where(task_type: "CLAIM_EXTRACTION", target_id: source.id).pluck(:status)).to eq([ "OPEN" ])
  end

  it "points Analyze text and Record an investigation at each other (acceptance 6)" do
    sign_up("paster@example.com")
    get "/analyze/new"
    expect(Nokogiri::HTML(response.body).css("main a[href='/investigations/new'], a[href='/investigations/new']").map(&:text)).to include("Record an investigation")
    get "/investigations/new"
    expect(Nokogiri::HTML(response.body).css("a[href='/analyze/new']").map(&:text)).to include("Analyze text")
  end
end
