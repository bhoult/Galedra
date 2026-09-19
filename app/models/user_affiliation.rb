# One self-declared affiliation of an account (config/affiliations.yml).
# Private: shown only as counts over groups large enough to hide anyone.
class UserAffiliation < ApplicationRecord
  belongs_to :user

  validates :affiliation, inclusion: { in: ->(_) { Affiliations.all } }, uniqueness: { scope: :user_id }
end
