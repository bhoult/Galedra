# A released scoring model (spec 02 §3.5, 05 §14): name, version, the exact
# config, and the hashes every trace cites. Projection of RELEASE_SCORING_MODEL.
class ScoringModel < ApplicationRecord
  include Projection

  belongs_to :contribution

  validates :name, :semantic_version, :config, :config_hash, :code_hash, :release_signature, :released_seq, presence: true
  validates :semantic_version, uniqueness: { scope: :name }

  def full_name = "#{name}@#{semantic_version}"
end
