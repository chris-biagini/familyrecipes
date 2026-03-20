# frozen_string_literal: true

# All tenant-scoped routes live inside an optional (/kitchens/:kitchen_slug) scope.
# When exactly one Kitchen exists, URLs are root-level (/recipes/bagels, /menu).
# When multiple Kitchens exist, URLs are scoped (/kitchens/ours/recipes/bagels).
#
# ApplicationController#default_url_options auto-injects kitchen_slug when the
# request arrived via a scoped URL, so all _path helpers adapt transparently.
# Use home_path (not kitchen_root_path) for homepage links — it picks the right root.
# LandingController handles the root URL: renders the sole kitchen's homepage
# directly, or a kitchen-list page when multiple exist.
Rails.application.routes.draw do
  get 'up', to: 'rails/health#show', as: :rails_health_check
  get 'manifest.json', to: 'pwa#manifest', as: :pwa_manifest
  get 'service-worker.js', to: 'pwa#service_worker', as: :pwa_service_worker

  root 'landing#show'

  get 'kitchens/:kitchen_slug', to: 'homepage#show', as: :kitchen_root

  scope '(/kitchens/:kitchen_slug)' do
    get 'recipes/:slug.md', to: 'recipes#show_markdown', as: :recipe_markdown, defaults: { format: 'text' }
    get 'recipes/:slug.html', to: 'recipes#show_html', as: :recipe_html, defaults: { format: 'html' }
    get 'recipes/:slug/content', to: 'recipes#content', as: :recipe_content
    post 'recipes/parse', to: 'recipes#parse', as: :recipe_parse
    post 'recipes/serialize', to: 'recipes#serialize', as: :recipe_serialize
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'ingredients', to: 'ingredients#index', as: :ingredients
    get 'ingredients/:ingredient_name/edit', to: 'ingredients#edit', as: :ingredient_edit
    get 'menu', to: 'menu#show', as: :menu
    patch 'menu/select', to: 'menu#select', as: :menu_select
    patch 'menu/quick_bites', to: 'menu#update_quick_bites', as: :menu_quick_bites
    get 'menu/quick_bites_content', to: 'menu#quick_bites_content', as: :menu_quick_bites_content
    post 'menu/parse_quick_bites', to: 'menu#parse_quick_bites', as: :menu_parse_quick_bites
    post 'menu/serialize_quick_bites', to: 'menu#serialize_quick_bites', as: :menu_serialize_quick_bites
    get 'groceries', to: 'groceries#show', as: :groceries
    patch 'groceries/check', to: 'groceries#check', as: :groceries_check
    patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
    patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
    get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
    patch 'categories/order', to: 'categories#update_order', as: :categories_order
    get 'categories/order_content', to: 'categories#order_content', as: :categories_order_content
    patch 'tags/update', to: 'tags#update_tags', as: :tags_update
    get 'tags/content', to: 'tags#content', as: :tags_content
    get 'export', to: 'exports#show', as: :export
    post 'import', to: 'imports#create', as: :import
    get 'settings', to: 'settings#show', as: :settings
    patch 'settings', to: 'settings#update'
    get 'settings/editor_frame', to: 'settings#editor_frame', as: :settings_editor_frame
    post 'ai_import', to: 'ai_import#create', as: :ai_import
    post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
    delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
    get 'usda/search', to: 'usda_search#search', as: :usda_search
    get 'usda/:fdc_id', to: 'usda_search#show', as: :usda_show
  end

  delete 'logout', to: 'dev_sessions#destroy', as: :logout

  get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login if Rails.env.local?
end
