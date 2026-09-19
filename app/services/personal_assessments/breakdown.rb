# frozen_string_literal: true

module PersonalAssessments
  # How the people who registered a view on a claim split, overall and by
  # self-declared affiliation. Counts only, and an affiliation appears only
  # when at least MIN_GROUP people holding it registered a view on the claim,
  # so no one's affiliation or view can be read off a small group. Political
  # neutrality (Article XVIII): the breakdown says how groups split, never
  # which group is right; the shared assessment stands apart from it.
  module Breakdown
    MIN_GROUP = 5
    NOTE = "Registered views are personal belief, not evidence: they never change Galedra's assessment. Affiliations are self-declared and shown only for groups of #{MIN_GROUP} or more."

    module_function

    def call(claim_id, min_group: MIN_GROUP)
      stances = PersonalAssessment.where(claim_id: claim_id).group(:stance).count
      agree = stances.fetch("AGREE", 0)
      disagree = stances.fetch("DISAGREE", 0)
      rows = UserAffiliation.joins("INNER JOIN personal_assessments pa ON pa.user_id = user_affiliations.user_id")
                            .where(pa: { claim_id: claim_id })
                            .group(:affiliation, "pa.stance").count
      by_affiliation = rows.keys.map(&:first).uniq.filter_map do |slug|
        a = rows.fetch([ slug, "AGREE" ], 0)
        d = rows.fetch([ slug, "DISAGREE" ], 0)
        next if a + d < min_group
        next unless Affiliations.valid?(slug)

        { affiliation: slug, label: Affiliations.label(slug), group: Affiliations.group_of(slug).label, agree: a, disagree: d, total: a + d }
      end.sort_by { |r| [ r[:group], -r[:total], r[:label] ] }
      { agree: agree, disagree: disagree, total: agree + disagree, min_group: min_group, by_affiliation: by_affiliation, note: NOTE }
    end
  end
end
