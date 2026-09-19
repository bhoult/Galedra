class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :custodied_key, dependent: nil
  belongs_to :admin_granted_by, class_name: "User", optional: true
  has_many :user_affiliations, dependent: :destroy
  has_many :personal_assessments, dependent: :destroy
  has_many :affiliation_requests, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  scope :admins, -> { where(admin: true) }

  def contributor = custodied_key&.contributor
end
