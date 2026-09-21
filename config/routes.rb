Rails.application.routes.draw do
  root "home#index"
  get "constitution", to: "home#constitution"
  get "faq", to: "home#faq"
  get "docs", to: "help#docs"
  get "docs/api", to: "help#api", as: :api_docs
  get "about", to: "help#about"
  get "licenses", to: "help#licenses"
  get "glossary", to: "help#glossary"
  get "contact", to: "help#contact"
  # Admin (Stage 24): a website role, never a ledger one.
  namespace :admin do
    resources :content_reviews, only: [ :index ] do
      member do
        post :settle
        post :restore
      end
    end
    resources :threads, only: [] do
      member { post :settle }
    end
    resources :affiliation_requests, only: [ :index ] do
      collection do
        post :merge
        post :add
        post :decline
      end
    end
    resources :users, only: [ :index ] do
      member do
        post :grant_admin
        post :revoke_admin
        post :grant_moderator
        post :revoke_moderator
      end
    end
  end

  resource :session
  resources :passwords, param: :token
  resources :users, only: [ :new, :create ]
  resources :assistants, only: [ :new, :create, :destroy ]
  resources :investigations, only: [ :index, :new, :create, :show ] do
    get :card, on: :member
  end
  get "adopt/:code", to: "adoptions#show", as: :adopt
  post "adopt/:code", to: "adoptions#create"

  resources :claims, only: [ :index, :show ] do
    get :card, on: :member
    post :topics, on: :member, to: "claims#tag"
    post :accept, on: :member, to: "claims#accept"
    post :place, on: :member, to: "claims#place"
    # A person's own view (spec 02 §3.6a): outside the log, in its own panel.
    resource :view, only: [ :create, :destroy ], controller: "personal_assessments"
  end
  resource :account, only: [ :show, :update ]
  # Stage 20: outlines of long sources, as trees of sections.
  resources :sections, only: [ :index, :show, :create ]
  resources :affiliation_requests, only: [ :create ]
  resources :feature_requests, only: [ :index, :show, :update ]
  resources :bug_reports, only: [ :new, :create, :index, :show, :update ]
  # Threads on determinations (Stage 37): one index of every thread on the node,
  # because a thread hangs off five kinds of object and the page each lives on is
  # not enough on its own — one on a source location is three clicks from
  # anywhere anyone starts.
  resources :threads, only: [ :index, :show, :create ] do
    member { post :respond }
  end
  get "topics", to: "topics#index", as: :topics
  get "topics/*path", to: "topics#show", as: :topic
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
  # Some clients look for OpenID discovery first; the same document answers.
  get "/.well-known/openid-configuration", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp/connect", to: "oauth/metadata#protected_resource"
  post "oauth/register", to: "oauth/clients#create"
  get "oauth/authorize", to: "oauth/authorizations#new", as: :oauth_authorize
  post "oauth/authorize", to: "oauth/authorizations#create"
  post "oauth/token", to: "oauth/tokens#create"
  post "oauth/revoke", to: "oauth/tokens#revoke"
  get "oauth/jwks", to: "oauth/metadata#jwks"
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
  resources :contributors, only: [ :index, :show ]
  resources :tasks, only: [ :index, :show ]
  get "weaknesses", to: "weaknesses#index"
  get "moderation", to: "moderation#index"
  get "snapshots/:seq", to: "snapshots#show", as: :snapshot

  namespace :api do
    namespace :v1 do
      get "meta", to: "meta#show"
      get "guidance", to: "guidance#show"
      get "openapi", to: "openapi#show"
      get "topics", to: "topics#index"
      resources :threads, only: [ :index, :show ] do
        post :respond, on: :member
      end
      get "log", to: "log#index"
      get "claims/:id/views", to: "claims#views"
      resources :sections, only: [ :index, :show ]
      get "inferences/:id", to: "inferences#show"
      resources :contributions, only: [ :create, :show ] do
        get :verify, on: :member
        get :redaction_manifest, on: :member
      end
      get "moderation", to: "moderation#index"
      resources :assistants, only: [ :create, :destroy ]
      post "custodied/contributions", to: "custodied#create"
      post "investigations", to: "investigations#create"
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
      get "contributors/top", to: "contributors#top"
      resources :contributors, only: [ :show ] do
        get :reputation, on: :member
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
