require "sidekiq/web"

Rails.application.routes.draw do
  get "/favicon.ico", to: redirect("/favicon.svg")

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"

  get "/synthesis_runs/seed_test", to: "synthesis_runs#seed_test", as: :seed_test_synthesis_runs
  resources :synthesis_runs, only: %i[index show new create]
  resources :grid_fits, only: %i[index show new create]
  resources :calibration_runs, only: %i[index show new create]
  resource :pipeline_config, only: %i[show edit update] do
    patch :reset
  end
  root "synthesis_runs#index"

  # Defines the root path route ("/")
  # root "posts#index"
end
