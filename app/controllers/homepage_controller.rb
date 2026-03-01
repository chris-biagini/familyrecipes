# frozen_string_literal: true

# Kitchen-scoped homepage, reached via /kitchens/:slug. Renders categories with
# their recipes. LandingController renders this same view for the sole-kitchen
# shortcut at the root URL.
class HomepageController < ApplicationController
  def show
    @site_config = Rails.configuration.site
    @categories = categories_with_recipes
  end

  private

  def categories_with_recipes
    current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
