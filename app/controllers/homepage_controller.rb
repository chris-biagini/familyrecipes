# frozen_string_literal: true

# Kitchen-scoped homepage, reached via /kitchens/:slug. Renders categories with
# their recipes. LandingController renders this same view for the sole-kitchen
# shortcut at the root URL.
class HomepageController < ApplicationController
  def show
    @site_config = Rails.configuration.site
    @categories = current_kitchen.categories.ordered.with_recipes.includes(:recipes)
  end
end
