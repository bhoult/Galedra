# OAuth clients that run in a browser (ChatGPT's connector callback page
# exchanges the code from the page itself) need CORS on the token,
# registration, revocation, and discovery endpoints. These are public OAuth
# endpoints by design; credentials are in the body, never in cookies.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/oauth/*", headers: :any, methods: %i[get post options], expose: %w[WWW-Authenticate]
    resource "/.well-known/*", headers: :any, methods: %i[get options]
    resource "/mcp*", headers: :any, methods: %i[get post options], expose: %w[WWW-Authenticate MCP-Protocol-Version]
  end
end
