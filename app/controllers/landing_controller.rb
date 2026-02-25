# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }
    @kitchens.size == 1 ? render_sole_kitchen_homepage : render('landing/show')
  end

  private

  def render_sole_kitchen_homepage
    set_current_tenant(@kitchens.first)
    @site_config = Rails.configuration.site
    @categories = current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
    render 'homepage/show'
  end
end
