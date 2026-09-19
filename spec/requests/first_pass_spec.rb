require "rails_helper"

RSpec.describe "One assistant can carry an outline to a postable state (owner request)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").first }

  def outline_bundle
    { "statement" => "An episode about remote work.",
      "source" => { "type" => "VIDEO", "title" => "An episode", "url" => "https://example.org/ep", "retrieved_at" => Time.now.utc.iso8601 },
      "sections" => [ { "handle" => "root", "heading" => "The episode", "sections" => [
        { "handle" => "leaf", "heading" => "On remote work", "locator" => { "type" => "TIME_RANGE", "start" => "00:00:00", "end" => "00:04:00" },
          "anchor" => "Remote work raises productivity, the host said.",
          "reading" => "Remote work raises productivity, the host said.\n\nHe cited a survey of four hundred people." } ] } ] }
  end

  it "records the outline, then records a leaf's claims and evidence itself, and the claims are scored" do
    outline = Investigations::Outline.call(token, outline_bundle, base_url: "http://www.example.com")
    expect(outline[:recorded]).to be(true)
    leaf_id = outline[:sections]["leaf"][:id]
    expect(Task.where(task_type: "CLAIM_EXTRACTION", status: "OPEN").count).to eq(1)

    # The same assistant does the first pass by recording, not by leasing its
    # own task: a principal never checks its own work, but recording what it
    # read is not checking, it is contributing.
    leaf = { "sources" => [ { "handle" => "s", "type" => "WEBSITE", "title" => "A survey", "url" => "https://example.org/survey",
                              "retrieved_at" => Time.now.utc.iso8601, "content_hash" => "sha256:#{'ab' * 32}" } ],
             "excerpts" => [ { "handle" => "x", "source" => "s", "text" => "Of 400 respondents, 62 percent reported higher productivity." } ],
             "claims" => [ { "handle" => "c", "text" => "A survey of 400 people reported 62 percent saying productivity rose.",
                             "type" => "QUANTITATIVE", "section" => leaf_id } ],
             "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "The survey reports the 62 percent figure." } ],
             "links" => [ { "evidence" => "e", "claim" => "c", "direction" => "SUPPORT" } ] }
    recorded = Investigations::Record.call(token, leaf, base_url: "http://www.example.com")
    expect(recorded[:recorded]).to be(true), recorded.inspect

    claim = Claim.find(recorded[:ids]["c"])
    seq = Contribution.maximum(:seq)
    result = Scoring::Score.call(claim, seq, Scoring::Registry.default_model)
    # Scored on the assistant's own reading, with no second agent involved.
    expect(result.assessment_state).not_to eq("INSUFFICIENT_EVIDENCE")
    expect(claim.accepted_seq).to be_present

    # And the checks that would raise confidence are open for anyone else.
    open_for_others = Task.where(target_id: claim.id, status: "OPEN")
    expect(open_for_others.pluck(:task_type)).to include("OPPOSING_EVIDENCE_SEARCH", "QUALIFIER_CHECK")
  end
end
