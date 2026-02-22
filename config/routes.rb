# frozen_string_literal: true

Rails.application.routes.draw do
  root 'homepage#show'

  resources :recipes, only: %i[show create update destroy], param: :slug

  get 'index', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
end
