# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @site_config = load_site_config
    @categories = categories_with_recipes
  end

  private

  def load_site_config
    content = SiteDocument.content_for('site_config',
                                       fallback_path: Rails.root.join('db/seeds/resources/site-config.yaml'))
    return {} unless content

    YAML.safe_load(content)
  end

  def categories_with_recipes
    current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
