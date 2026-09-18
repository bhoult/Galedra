# A server-custodied private key for a browser user (spec 05 §2), encrypted at
# rest with Active Record Encryption. Not a projection: it survives replay.
class CustodiedKey < ApplicationRecord
  belongs_to :contributor
  belongs_to :user, optional: true

  encrypts :encrypted_private_key

  validates :contributor_id, uniqueness: true
  validates :encrypted_private_key, presence: true
  validate :never_the_system_key

  private

  def never_the_system_key
    return unless contributor&.system?

    errors.add(:contributor, "must not be the system key; it lives only in the environment")
  end
end
