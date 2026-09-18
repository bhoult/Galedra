# A recorded investigation's receipt, keyed by token and bundle digest, so a
# repeated submission (a retried POST, or a write link fetched twice) returns
# the first result instead of recording again.
class InvestigationReceipt < ApplicationRecord
  belongs_to :assistant_token

  def self.digest_for(bundle) = Crypto::Hashing.json(bundle)
end
