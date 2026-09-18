# A cached, cited summary (spec 04 §10). Cache only.
class Summary < ApplicationRecord
  TYPES = %w[SHORT STANDARD].freeze
  belongs_to :claim
  belongs_to :scoring_model
end
