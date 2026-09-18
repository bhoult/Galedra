class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :custodied_key, dependent: nil

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
