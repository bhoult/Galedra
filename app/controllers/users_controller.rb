# Sign-up: a user plus a server-custodied key registered through the log. The
# first account becomes the admin (Stage 24).
class UsersController < ApplicationController
  allow_unauthenticated_access

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.require(:user).permit(:email_address, :password, :password_confirmation))
    if @user.valid?
      Users::Admins.create_first_or_ordinary!(@user)
      Crypto::Custody.create_server_custodied(user: @user, display_name: @user.email_address.split("@").first)
      start_new_session_for @user
      redirect_to root_path, notice: "Signed up. A server-held signing key was registered for you.#{' You are the first account, so you are an admin.' if @user.admin?}"
    else
      render :new, status: :unprocessable_content
    end
  end
end
