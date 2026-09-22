# The task board (spec 06 §5).
class TasksController < ApplicationController
  allow_unauthenticated_access

  # A board of categories, not a list of tasks. Nobody hands their assistant one
  # task at a time: they want to see where the work is and point it at a kind of
  # it (owner, 2026-09-22). The per-task page still exists for reading one.
  #
  # Counted in answers wanted rather than in tasks. Most tasks want three
  # independent answers, so a count of tasks tells a person their afternoon
  # achieved nothing while they were in fact working — the same confusion four
  # assistants have had with `open` and `open_for_you` over the API.
  def index
    Tasks::Lease.expire_stale!
    @type = params[:type].presence_in(Tasks::Types::ALL)
    @domain = params[:domain].presence_in(Audits::Policy.domains)

    open = Task.where(status: %w[OPEN LEASED])
    @by_type = wanted_by(open, :task_type)
    @by_domain = wanted_by(@type ? open.where(task_type: @type) : open, :domain)

    scope = open
    scope = scope.where(task_type: @type) if @type
    scope = scope.where(domain: @domain) if @domain
    @wanted = @by_type.values.sum
    @shown = scope.order(priority: :desc, created_at: :asc).limit(25)
    @completed = Task.where(status: "COMPLETE").order(updated_at: :desc).limit(10)
  end

  private

  # Answers still wanted, grouped. One query for the tasks and one for the
  # assignments underneath them, whatever the number of groups.
  def wanted_by(scope, column)
    tasks = scope.select(:id, :required_assignments, column).to_a
    slots = Task.open_slots_for(tasks)
    tasks.each_with_object(Hash.new(0)) do |task, tally|
      left = slots.fetch(task.id, 0)
      tally[task.public_send(column)] += left if left.positive?
    end.sort_by { |_, n| -n }.to_h
  end

  public

  def show
    @task = Task.find(params[:id])
    @target = @task.target
  end
end
