# frozen_string_literal: true

# Kitchen-scoped homepage, reached via /kitchens/:slug. Renders categories with
# their recipes grouped by category. LandingController renders this same view
# for the sole-kitchen shortcut at the root URL.
#
# - Category: ordered categories with eager-loaded recipes
# - Kitchen: site title and branding read from current_kitchen
class HomepageController < ApplicationController
  before_action :prevent_html_caching, only: :show

  def show
    @categories = current_kitchen.categories.with_recipes.ordered.includes(recipes: :tags)
  end
end
