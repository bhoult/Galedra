# The "Connect an assistant" page (Stage 12). Works signed out: the principal
# is then a fresh anonymous key. The token is shown once.
class AssistantsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_to new_assistant_path, alert: "Too many tokens minted from this address. Try again later." }

  ASSISTANTS = [
    [ "Claude", "anthropic" ], [ "ChatGPT", "openai" ], [ "Grok", "xai" ], [ "Gemini", "google" ], [ "Another assistant", "other" ]
  ].freeze

  def new
    @tokens = authenticated? ? AssistantToken.where(user: Current.user).order(created_at: :desc) : AssistantToken.none
  end

  def create
    choice = params.fetch(:assistant, {})
    name, provider = ASSISTANTS.find { |_, p| p == choice[:provider] } || ASSISTANTS.last
    name = choice[:name].presence || name
    @token, @plaintext = Assistants::Connect.call(user: authenticated? ? Current.user : nil, name: name, provider: provider, model: choice[:model])
    render :created
  rescue ArgumentError => e
    redirect_to new_assistant_path, alert: e.message
  end

  def destroy
    token = AssistantToken.find(params[:id])
    return redirect_to new_assistant_path, alert: "Not your assistant." unless authenticated? && token.user == Current.user

    Assistants::Revoke.call(token)
    redirect_to new_assistant_path, notice: "Assistant disconnected. The revocation is in the public log."
  end
end
