require "rails_helper"

# The board listed a hundred individual tasks. Nobody hands their assistant one
# task at a time: they want to see where the work is and point it at a kind of
# it (owner, 2026-09-22).
RSpec.describe "Where the work is", type: :request do
  include GraphHelpers
  before { release_models }

  # Creating a claim does not always open a task in a bare fixture, so the board
  # is given work to count rather than asked to count whatever happened.
  def open_tasks
    pair, = register_key
    claim = create_claim(pair, "A claim that needs checking.")
    create_task("OPPOSING_EVIDENCE_SEARCH", claim, required_assignments: 3)
    create_task("QUALIFIER_CHECK", claim, required_assignments: 3)
    claim
  end

  it "counts answers wanted by kind, not tasks" do
    open_tasks
    get "/tasks"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("answers still wanted")
    # A count of tasks would tell a person their afternoon achieved nothing:
    # most tasks want three answers and a task only closes on the third.
    wanted = Task.where(status: %w[OPEN LEASED]).to_a
    slots = Task.open_slots_for(wanted).values.sum
    expect(response.body).to include(ActiveSupport::NumberHelper.number_to_delimited(slots))
  end

  it "lets a reader narrow to one kind, and shows the subjects within it" do
    open_tasks
    type = Task.where(status: "OPEN").first.task_type

    get "/tasks", params: { type: type }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(type.tr("_", " ").downcase)
    expect(response.body).to include("Point your assistant at")
  end

  # The point of choosing a category: words naming the filters, not a task id.
  it "hands over instructions that name the chosen filters" do
    open_tasks
    get "/tasks", params: { type: "OPPOSING_EVIDENCE_SEARCH", domain: "general" }

    expect(response.body).to include("next_task")
    expect(response.body).to include("OPPOSING_EVIDENCE_SEARCH")
    expect(response.body).to include("general")
    expect(response.body).to include("#{Ledger::Node.url}/mcp")
    expect(response.body).to include("introduce_yourself")
    expect(response.body).to include("open_for_you"), "quoting the queue total tells them nothing moved"
    expect(response.body).to include("Do not spend my whole allowance")
  end

  # A filter that is not a real type must not reach the query.
  it "ignores a kind or subject this node does not have" do
    open_tasks
    get "/tasks", params: { type: "NONSENSE", domain: "atlantis" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Point your assistant at")
  end

  it "keeps the individual tasks available, behind a fold" do
    open_tasks
    get "/tasks"

    expect(response.body).to include("if you want to read one")
    expect(response.body).to include("/tasks/#{Task.where(status: 'OPEN').first.id}")
  end
end
