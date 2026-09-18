# frozen_string_literal: true

module Audits
  # config/audit_policy.yml (spec 05 §7–§10).
  module Policy
    module_function

    def config
      @config ||= Rails.application.config_for(:audit_policy).to_h.deep_stringify_keys
    end

    def version = config.fetch("policy_version")
    # The configured domains plus every domain the topic vocabulary maps to (Stage 15).
    def domains = (config.fetch("domains") + Topics.domains).uniq
    def default_domain = config.fetch("default_domain")
    def manual_task_type = config.fetch("manual_task_type")

    def required_confirmations(downstream_count)
      band = config.fetch("high_impact").find { |b| b["max_downstream"].nil? || downstream_count <= b["max_downstream"] }
      [ band.fetch("confirming_audits"), band.fetch("opposing_search") ]
    end

    def reset!
      @config = nil
    end
  end
end
