Rails.application.routes.draw do
  root "home#index"

  resource :session
  resources :passwords, param: :token

  namespace :api do
    namespace :v1 do
      get "meta", to: "meta#show"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
