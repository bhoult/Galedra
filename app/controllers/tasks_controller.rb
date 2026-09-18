# The task board (spec 06 §5).
class TasksController < ApplicationController
  allow_unauthenticated_access

  def index
    Tasks::Lease.expire_stale!
    @tasks = Task.where(status: %w[OPEN LEASED]).order(priority: :desc, created_at: :asc).limit(100)
    @completed = Task.where(status: "COMPLETE").order(updated_at: :desc).limit(20)
  end

  def show
    @task = Task.find(params[:id])
    @target = @task.target
  end
end
