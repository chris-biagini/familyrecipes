# frozen_string_literal: true

# Root route handler. When exactly one Kitchen exists, renders the homepage
# directly (no redirect) so single-kitchen installs get clean root-level URLs.
# When multiple Kitchens exist, renders a kitchen-list landing page. Skips
# set_kitchen_from_path because the root URL has no slug.
#
# - Kitchen: tenant lookup (bypasses ActsAsTenant scoping)
# - HomepageController: shares the homepage/show view for the sole-kitchen case
class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }
    @kitchens.size == 1 ? render_sole_kitchen_homepage : render('landing/show')
  end

  private

  def render_sole_kitchen_homepage
    set_current_tenant(@kitchens.first)
    @categories = current_kitchen.categories.ordered.with_recipes.includes(:recipes)
    @all_categories = current_kitchen.categories.ordered
    render 'homepage/show'
  end
end
