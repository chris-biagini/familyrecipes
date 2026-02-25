# frozen_string_literal: true

Rails.application.routes.draw do
  get 'up', to: 'rails/health#show', as: :rails_health_check

  root 'landing#show'

  scope 'kitchens/:kitchen_slug' do
    get '/', to: 'homepage#show', as: :kitchen_root
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'ingredients', to: 'ingredients#index', as: :ingredients
    get 'groceries', to: 'groceries#show', as: :groceries
    get 'groceries/state', to: 'groceries#state', as: :groceries_state
    patch 'groceries/select', to: 'groceries#select', as: :groceries_select
    patch 'groceries/check', to: 'groceries#check', as: :groceries_check
    patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
    delete 'groceries/clear', to: 'groceries#clear', as: :groceries_clear
    patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
    patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
    get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
    post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
    delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
  end

  delete 'logout', to: 'dev_sessions#destroy', as: :logout

  get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login if Rails.env.local?
end
