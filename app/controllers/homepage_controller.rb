# frozen_string_literal: true

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
