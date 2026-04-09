# frozen_string_literal: true

# Root route handler. No kitchens → redirects to /new (kitchen creation).
# One Kitchen → renders its homepage directly (clean root-level URLs).
# Multiple Kitchens → renders a kitchen-list landing page with create/join links.
# Skips set_kitchen_from_path because the root URL has no slug.
#
# - Kitchen: tenant lookup (bypasses ActsAsTenant scoping)
# - HomepageController: shares the homepage/show view for the sole-kitchen case
# - KitchensController: creation flow at /new
# - JoinsController: join flow at /join
class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :prevent_html_caching, only: :show

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }

    return redirect_to new_kitchen_path if @kitchens.empty?

    @kitchens.size == 1 ? render_sole_kitchen_homepage : render('landing/show')
  end

  private

  def render_sole_kitchen_homepage
    set_current_tenant(@kitchens.first)
    @categories = current_kitchen.categories.with_recipes.ordered.includes(recipes: :tags)
    render 'homepage/show'
  end
end
