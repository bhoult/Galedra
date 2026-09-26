# frozen_string_literal: true

module Users
  # The name a person chooses to sign under, which goes into the public log in
  # their key's REGISTER_KEY and can never be taken out again. It used to be the
  # part of their email address before the "@", which published an identifier
  # they never chose to publish (privacy policy, 2026-09-23). Now it is what they
  # typed, or nothing.
  module PublicName
    MAX = 60

    module_function

    def chosen(text)
      name = text.to_s.squish
      name.empty? ? nil : name[0, MAX]
    end
  end
end
