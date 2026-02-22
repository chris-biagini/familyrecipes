# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @site_config = load_site_config
    @categories = categories_with_recipes
  end

  private

  def load_site_config = YAML.safe_load_file(Rails.root.join('resources/site-config.yaml'))

  def categories_with_recipes
    Category.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
