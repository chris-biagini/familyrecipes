# frozen_string_literal: true

Rails.application.routes.draw do
  root 'homepage#show'

  resources :recipes, only: %i[show create update destroy], param: :slug

  get 'index', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
  patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
  patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
end
