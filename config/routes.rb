# frozen_string_literal: true

Rails.application.routes.draw do
  get 'up', to: 'rails/health#show', as: :rails_health_check

  root 'landing#show'

  scope 'kitchens/:kitchen_slug' do
    get '/', to: 'homepage#show', as: :kitchen_root
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'index', to: 'ingredients#index', as: :ingredients
    get 'groceries', to: 'groceries#show', as: :groceries
    patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
    patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
    post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
    delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
  end

  match 'auth/:provider/callback', to: 'omniauth_callbacks#create', as: :omniauth_callback, via: %i[get post]
  get 'auth/failure', to: 'omniauth_callbacks#failure'
  delete 'logout', to: 'omniauth_callbacks#destroy', as: :logout
  get 'login', to: 'sessions#new', as: :login

  if Rails.env.development? || Rails.env.test?
    get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login
    get 'dev/logout', to: 'dev_sessions#destroy', as: :dev_logout
  end
end
