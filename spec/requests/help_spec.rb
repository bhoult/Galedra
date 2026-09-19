require "rails_helper"

RSpec.describe "Help menu and pages (Stage 24)", type: :request do
  it "shows Check, Browse, and Help menus to a visitor, with no Admin menu" do
    get "/"
    body = response.body
    expect(body).to include("<summary>Check</summary>")
    expect(body).to include("<summary>Browse</summary>")
    expect(body).to include("<summary>Help</summary>")
    expect(body).not_to include("<summary>Admin</summary>")
    expect(body).to include(">FAQ<").and include(">Docs<").and include(">Constitution<").and include(">About<")
    help = body[body.index("<summary>Help</summary>")..]
    expect(help).to include(">Connect an assistant<")
    expect(body).not_to include("Analyze text")
  end

  it "renders the docs page from the README with the pointers an integrator needs" do
    get "/docs"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OpenAPI description")
    expect(response.body).to include("/api/v1/openapi")
    expect(response.body).to include("skills/galedra.md")
    expect(response.body).to include("The problem")
  end

  it "shows every licence in the stack in full, with what is in force today" do
    get "/licenses"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AGPL-3.0-or-later")
    expect(response.body).to include("GNU AFFERO GENERAL PUBLIC LICENSE")
    expect(response.body).to include("Galedra Licensing Policy")
    expect(response.body).to include("ODbL-1.0").and include("Apache-2.0").and include("CC0-1.0")
    expect(Governance::Licenses.code_license_name).to eq("AGPL-3.0-or-later")
    %w[AGPL-3.0-or-later Apache-2.0 ODbL-1.0 CC0-1.0 CC-BY-4.0].each do |id|
      expect(response.body).to include("id=\"license-#{id}\"")
    end
    expect(response.body).to include("GNU AFFERO GENERAL PUBLIC LICENSE")
    get "/"
    help = response.body[response.body.index("<summary>Help</summary>")..]
    expect(help).to include(">Licences<")
  end

  it "defines every kind of work and the core terms in the glossary" do
    get "/glossary"
    expect(response).to have_http_status(:ok)
    %w[check task audit accept correct review personal-view moderate].each { |id| expect(response.body).to include("id=\"#{id}\"") }
    expect(response.body).to include("Opposing evidence search").and include("Independence group").and include("Provisional")
    get "/"
    help = response.body[response.body.index("<summary>Help</summary>")..]
    expect(help).to include(">Glossary<")
  end

  it "renders the about page with the running revision, the node, and the constitution hash" do
    get "/about"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Governance::Software.revision)
    expect(response.body).to include(Governance::Software::REPOSITORY)
    expect(response.body).to include(Crypto::SystemKey.key_id)
    expect(response.body).to include(Governance::Constitution.new.digest)
    expect(response.body).to include("ODbL-1.0")
  end

  it "reads the revision from a REVISION file first" do
    Governance::Software.instance_variable_set(:@revision, nil)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(Governance::Software::REVISION_FILE).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(Governance::Software::REVISION_FILE).and_return("stage-24-admin-nav\n")
    expect(Governance::Software.revision).to eq("stage-24-admin-nav")
  ensure
    Governance::Software.instance_variable_set(:@revision, nil)
  end
end
