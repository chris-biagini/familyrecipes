# frozen_string_literal: true

Rails.application.routes.draw do # rubocop:disable Metrics/BlockLength
  get 'up', to: 'rails/health#show', as: :rails_health_check
  get 'manifest.json', to: 'pwa#manifest', as: :pwa_manifest

  root 'landing#show'

  get 'kitchens/:kitchen_slug', to: 'homepage#show', as: :kitchen_root

  scope '(/kitchens/:kitchen_slug)' do
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'ingredients', to: 'ingredients#index', as: :ingredients
    get 'ingredients/:ingredient_name/edit', to: 'ingredients#edit', as: :ingredient_edit
    get 'menu', to: 'menu#show', as: :menu
    patch 'menu/select', to: 'menu#select', as: :menu_select
    patch 'menu/select_all', to: 'menu#select_all', as: :menu_select_all
    delete 'menu/clear', to: 'menu#clear', as: :menu_clear
    patch 'menu/quick_bites', to: 'menu#update_quick_bites', as: :menu_quick_bites
    get 'menu/quick_bites_content', to: 'menu#quick_bites_content', as: :menu_quick_bites_content
    get 'menu/state', to: 'menu#state', as: :menu_state
    get 'groceries', to: 'groceries#show', as: :groceries
    get 'groceries/state', to: 'groceries#state', as: :groceries_state
    patch 'groceries/check', to: 'groceries#check', as: :groceries_check
    patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
    patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
    get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
    post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
    delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
  end

  delete 'logout', to: 'dev_sessions#destroy', as: :logout

  get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login if Rails.env.local?
end
