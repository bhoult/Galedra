class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Ledger tables use UUIDv7 primary keys (spec README conventions), generated
  # here so ids are time-ordered and never depend on a database default.
  before_create :assign_uuid_v7

  private

  def assign_uuid_v7
    return unless self.class.columns_hash["id"]&.type == :uuid

    self.id ||= SecureRandom.uuid_v7
  end
end
