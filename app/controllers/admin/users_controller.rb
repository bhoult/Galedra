# Admin → Users (Stage 24): who has an account, who is an admin or a
# moderator, and the buttons to change that. Admin is a website role; the
# moderator flag is what Governance::Moderators reads, and /api/v1/meta
# publishes the resulting key ids so the power is visible.
module Admin
  class UsersController < ApplicationController
    before_action :require_admin

    def index
      @users = User.order(:created_at).includes(custodied_key: :contributor)
      @admin_count = User.admins.count
    end

    def grant_admin
      Users::Admins.grant_admin!(User.find(params[:id]), by: Current.user)
      redirect_to admin_users_path, notice: "Admin granted."
    end

    def revoke_admin
      Users::Admins.revoke_admin!(User.find(params[:id]), by: Current.user)
      redirect_to admin_users_path, notice: "Admin revoked."
    end

    def grant_moderator
      Users::Admins.set_moderator!(User.find(params[:id]), true, by: Current.user)
      redirect_to admin_users_path, notice: "Moderator appointed. The key is now listed in /api/v1/meta."
    end

    def revoke_moderator
      Users::Admins.set_moderator!(User.find(params[:id]), false, by: Current.user)
      redirect_to admin_users_path, notice: "Moderator removed."
    end
  end
end
