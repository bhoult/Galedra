# frozen_string_literal: true

module Api
  module V1
    # Tasks (spec 04 §7, 06 §2). Leasing and releasing are signed requests
    # (eir-lease-v1); results go through POST /contributions as TASK_RESULT.
    class TasksController < BaseController
      LEASE_PROTOCOL = "eir-lease-v1"

      rate_limit to: 60, within: 1.minute, by: -> { lease_key }, only: [ :next, :release ]

      # POST /api/v1/tasks/next  body: signed {payload: {types: [], domains: []}}
      def next
        contributor, delegation, payload = Contributions::SignedRequest.verify!(body, protocol: LEASE_PROTOCOL)
        types = Array(payload["types"].presence || params[:types].to_s.split(",")).map(&:to_s).reject(&:empty?)
        domains = Array(payload["domains"].presence || params[:domains].to_s.split(",")).map(&:to_s).reject(&:empty?)
        assignment = Tasks::Lease.next(contributor: contributor, delegation: delegation, types: types, domains: domains)
        return head :no_content if assignment.nil?

        render json: { assignment: assignment_json(assignment), packet: assignment.task.packet }
      end

      def show
        task = Task.find(params[:id])
        render json: { task: task_json(task) }
      end

      # POST /api/v1/tasks/:id/release  body: signed {payload: {}}
      def release
        contributor, _delegation, _payload = Contributions::SignedRequest.verify!(body, protocol: LEASE_PROTOCOL)
        task = Task.find(params[:id])
        assignment = TaskAssignment.latest_for(task.id, contributor.id)
        raise Ledger::Rejected.new([ { code: "LEASE_MISSING", path: "$", detail: "this task is not leased to the signer" } ]) if assignment.nil?

        render json: { assignment: assignment_json(Tasks::Lease.release(assignment)) }
      end

      private

      def body
        @body ||= JSON.parse(request.raw_post.presence || "{}")
      rescue JSON::ParserError
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$", detail: "body is not valid JSON" } ])
      end

      def lease_key
        body["signer_key_id"].presence || request.remote_ip
      rescue Ledger::Rejected
        request.remote_ip
      end

      def assignment_json(a)
        { id: a.id, task_id: a.task_id, status: a.status, lease_expires_at: a.lease_expires_at.utc.iso8601, result_contribution_id: a.result_contribution_id }
      end

      def task_json(task)
        Tasks::Lease.expire_stale!
        task.reload
        base = {
          id: task.id, task_type: task.task_type, domain: task.domain, target_type: task.target_type, target_id: task.target_id,
          status: task.status, priority: task.priority.to_s("F"), required_assignments: task.required_assignments,
          slots: { required: task.required_assignments, leased: task.active_assignments.count, submitted: task.submitted_assignments.count },
          packet: task.packet, packet_hash: task.packet_hash, issued_seq: task.issued_seq, estimated_cost: task.spec[:cost],
          audit_requirement: "sampled per #{Audits::Policy.version}; results stay provisional until audited CONFIRMED",
          lease_command: "ruby examples/agent/agent.rb run --base-url <ledger> --key-file <key.json> --delegation <id> --types #{task.task_type} --once"
        }
        # Blind independent verification (04 §3.1): results appear only once the task is closed.
        base[:results] = task.closed? ? task.submitted_assignments.map { |a| { contributor_id: a.contributor_id, result_contribution_id: a.result_contribution_id } } : nil
        base
      end
    end
  end
end
