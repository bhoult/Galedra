Rails.application.routes.draw do
  root "home#index"
  get "constitution", to: "home#constitution"
  get "faq", to: "home#faq"

  resource :session
  resources :passwords, param: :token
  resources :users, only: [ :new, :create ]
  resources :assistants, only: [ :new, :create, :destroy ]
  resources :investigations, only: [ :new, :create ]
  get "adopt/:code", to: "adoptions#show", as: :adopt
  post "adopt/:code", to: "adoptions#create"

  resources :claims, only: [ :index, :show ] do
    get :card, on: :member
  end
  post "mcp", to: "mcp#create"
  get "mcp", to: "mcp#show"
  # The authenticated door: answers 401 with resource metadata until the
  # connector completes OAuth, so every call is attributed (Stage 16).
  post "mcp/connect", to: "mcp#create", defaults: { require_auth: true }, as: :mcp_connect
  get "mcp/connect", to: "mcp#show"
  # The token may travel in the URL for connector screens that take only a URL.
  post "mcp/:token", to: "mcp#create", as: :mcp_with_token, constraints: { token: /gal_[A-Za-z0-9_-]+/ }
  get "mcp/:token", to: "mcp#show", constraints: { token: /gal_[A-Za-z0-9_-]+/ }

  # OAuth 2.1 for connectors (Stage 16)
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp/connect", to: "oauth/metadata#protected_resource"
  post "oauth/register", to: "oauth/clients#create"
  get "oauth/authorize", to: "oauth/authorizations#new", as: :oauth_authorize
  post "oauth/authorize", to: "oauth/authorizations#create"
  post "oauth/token", to: "oauth/tokens#create"
  post "oauth/revoke", to: "oauth/tokens#revoke"
  resources :sources, only: [ :show ] do
    member do
      get :analyze
      post :claims, to: "sources#create_claims"
      post :tasks, to: "sources#create_tasks"
    end
  end
  resource :analyze, only: [ :new, :create ], controller: "analyze"
  resources :evidence, only: [ :show ]
  resources :contributions, only: [ :index, :show ]
  resources :contributors, only: [ :show ]
  resources :tasks, only: [ :index, :show ]
  get "weaknesses", to: "weaknesses#index"
  get "moderation", to: "moderation#index"
  get "snapshots/:seq", to: "snapshots#show", as: :snapshot

  namespace :api do
    namespace :v1 do
      get "meta", to: "meta#show"
      get "openapi", to: "openapi#show"
      get "log", to: "log#index"
      resources :contributions, only: [ :create, :show ] do
        get :verify, on: :member
        get :redaction_manifest, on: :member
      end
      get "moderation", to: "moderation#index"
      resources :assistants, only: [ :create, :destroy ]
      post "custodied/contributions", to: "custodied#create"
      post "investigations", to: "investigations#create"
      get "investigations/record", to: "investigations#record_by_link", as: :record_investigation
      # Some fetchers strip query strings from links; the bundle may ride in the path.
      get "investigations/record/:bundle", to: "investigations#record_by_link", constraints: { bundle: /[A-Za-z0-9_\-=]+/ }, as: :record_investigation_path_form
      post "tasks/next", to: "tasks#next"
      resources :tasks, only: [ :show ] do
        post :release, on: :member
      end
      get "schemas/:name", to: "schemas#show", as: :schema
      resources :sources, only: [ :show ] do
        get :locations, on: :member
      end
      resources :claims, only: [ :index, :show ] do
        get :evidence, on: :member
        get :score, on: :member, to: "scores#score"
        get :trace, on: :member, to: "scores#trace"
        get :compare, on: :member, to: "scores#compare"
        get :why, on: :member, to: "scores#why"
        get :summary, on: :member, to: "scores#summary"
      end
      get "weaknesses", to: "weaknesses#index"
      get "snapshots", to: "snapshots#index"
      get "snapshots/:seq", to: "snapshots#show", as: :snapshot
      get "scoring-models", to: "scoring_models#index"
      post "admin/snapshots", to: "admin#create_snapshot"
      post "admin/recompute", to: "admin#recompute"
      resources :evidence, only: [ :show ]
      resources :contributors, only: [ :show ] do
        get :reputation, on: :member
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
