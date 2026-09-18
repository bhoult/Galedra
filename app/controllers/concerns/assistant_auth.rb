# Bearer authentication for connected assistants (Stage 12).
module AssistantAuth
  extend ActiveSupport::Concern

  private

  def current_assistant_token
    return @current_assistant_token if defined?(@current_assistant_token)

    header = request.authorization.to_s
    plaintext = header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")
    @current_assistant_token = AssistantToken.find_by_token(plaintext)
  end

  def authenticate_assistant!
    token = current_assistant_token
    if token.nil? || !token.usable?
      render json: { errors: [ { code: "TOKEN_INVALID", path: "$", detail: "send a valid assistant token as Authorization: Bearer <token>; mint one at /assistants/new" } ] }, status: :unauthorized
    end
  end

  def assistant_rate_limit_key
    current_assistant_token&.token_digest || request.remote_ip
  end

  def too_many_requests
    render json: { errors: [ { code: "RATE_LIMITED", path: "$", detail: "too many requests; slow down and try again in a minute" } ] }, status: :too_many_requests
  end
end
