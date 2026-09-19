# frozen_string_literal: true

module Tasks
  # Opens the verification tasks every counted claim gets (opposing search,
  # qualifier check, and evidence verification against a passage), once per
  # claim and type. Investigations::Record calls it on recording; Stage 21
  # also calls it when an extraction result is accepted, so claims a volunteer
  # extracted and a different principal accepted are checked like any other.
  module OpenVerification
    module_function

    def call(claims, created_by: nil, priority_factor: "1", location_for: ->(_claim) { nil })
      opened = 0
      claims.each do |claim|
        domain = Topics.domain_for_claim(claim, Contribution.maximum(:seq)) || Audits::Policy.default_domain
        section_id = ClaimPlacement.live.where(claim_id: claim.id).order(:created_seq).first&.section_id
        %w[OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK].each do |type|
          next if Task.where(task_type: type, target_type: "CLAIM", target_id: claim.id).exists?

          Create.call(task_type: type, target: claim, domain: domain, created_by: created_by, priority_factor: priority_factor, section_id: section_id)
          opened += 1
        end
        location = location_for.call(claim)
        next if location.nil? || Task.where(task_type: "EVIDENCE_VERIFICATION", target_type: "CLAIM", target_id: claim.id).exists?

        Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, domain: domain, location: location, created_by: created_by, priority_factor: priority_factor, section_id: section_id)
        opened += 1
      end
      opened
    end

    # For claims born of an accepted extraction: verify against the leaf's anchor.
    def for_extraction(contribution, created_by: nil)
      claims = Claim.where(contribution_id: contribution.id).to_a
      return 0 if claims.empty?

      call(claims, created_by: created_by, location_for: lambda { |claim|
        section = ClaimPlacement.live.where(claim_id: claim.id).order(:created_seq).first&.section
        section&.location
      })
    end
  end
end
