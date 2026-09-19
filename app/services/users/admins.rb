# frozen_string_literal: true

module Users
  # Application administrators (Stage 24). Admin is a website role, not a
  # ledger role: it grants no power over the log. The first account is an
  # admin; admins grant and revoke admin and moderator on others. The last
  # admin cannot be revoked, so the site is never left without one. Every
  # grant records who made it and when.
  module Admins
    class Refused < StandardError; end

    module_function

    # Wraps sign-up so that the first account, and only the first, is an admin
    # even when two people sign up at once.
    def create_first_or_ordinary!(user)
      User.transaction do
        User.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
        if User.none?
          user.admin = true
          user.admin_granted_at = Time.current
        end
        user.save!
      end
      user
    end

    def grant_admin!(user, by:)
      raise Refused, "only an admin may grant admin" unless by&.admin?
      return user if user.admin?

      user.update!(admin: true, admin_granted_by_id: by.id, admin_granted_at: Time.current)
    end

    def revoke_admin!(user, by:)
      raise Refused, "only an admin may revoke admin" unless by&.admin?
      return user unless user.admin?
      raise Refused, "the last admin cannot be revoked" if User.where(admin: true).count <= 1

      user.update!(admin: false, admin_granted_by_id: by.id, admin_granted_at: Time.current)
    end

    # Moderator appointment is the owner's reserved decision; until it is made
    # in the log, an admin flags the account, and /api/v1/meta publishes the key.
    def set_moderator!(user, value, by:)
      raise Refused, "only an admin may appoint moderators" unless by&.admin?

      user.update!(moderator: value)
    end

    def lock_key = Zlib.crc32("users.first_admin")
  end
end
