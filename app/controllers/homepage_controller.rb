# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @site_config = load_site_config
    @categories = categories_with_recipes
  end

  private

  def load_site_config
    doc = current_kitchen.site_documents.find_by(name: 'site_config')
    return YAML.safe_load(doc.content) if doc

    YAML.safe_load_file(Rails.root.join('db/seeds/resources/site-config.yaml'))
  end

  def categories_with_recipes
    current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
