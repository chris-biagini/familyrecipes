# frozen_string_literal: true

# Kitchen-scoped homepage, reached via /kitchens/:slug. Renders categories with
# their recipes grouped by category. LandingController renders this same view
# for the sole-kitchen shortcut at the root URL.
#
# - Category: ordered categories with eager-loaded recipes
# - Kitchen: site title and branding read from current_kitchen
class HomepageController < ApplicationController
  def show
    @categories = current_kitchen.categories.ordered.with_recipes.includes(:recipes)
    @all_categories = current_kitchen.categories.ordered
  end
end
