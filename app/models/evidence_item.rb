# A specific observation anchored to a source location (spec 02 §3.3).
class EvidenceItem < ApplicationRecord
  include GraphProjection

  OBSERVATION_TYPES = %w[DIRECT_TEXT MEASUREMENT DATASET_RESULT ARCHAEOLOGICAL EYEWITNESS HEARSAY CALCULATION EXPERT_ANALYSIS MODEL_OUTPUT OTHER].freeze
  AUTHENTICITY = %w[VERIFIED UNVERIFIED DOUBTFUL].freeze
  EXTRACTION = %w[VERIFIED UNVERIFIED].freeze
  DEFAULT_ASSESSMENT = { "authenticity" => "UNVERIFIED", "extraction" => "UNVERIFIED" }.freeze

  belongs_to :source_location
  belongs_to :independence_group, optional: true
  has_many :evidence_claim_links, dependent: nil
  has_many :assignments, class_name: "IndependenceGroupAssignment", dependent: nil

  validates :observation_type, inclusion: { in: OBSERVATION_TYPES }
  validates :statement, presence: true

  def independence_group_at(seq)
    assignments.counted_at(seq).order(accepted_seq: :desc).first&.independence_group
  end
end
