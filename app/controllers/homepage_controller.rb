# frozen_string_literal: true

# Kitchen-scoped homepage, reached via /kitchens/:slug. Renders categories with
# their recipes grouped by category. LandingController renders this same view
# for the sole-kitchen shortcut at the root URL.
#
# - Category: ordered categories with eager-loaded recipes
# - Rails.configuration.site: site title and branding for the layout
class HomepageController < ApplicationController
  def show
    @site_config = Rails.configuration.site
    @categories = current_kitchen.categories.ordered.with_recipes.includes(:recipes)
    @all_categories = current_kitchen.categories.ordered
  end
end
