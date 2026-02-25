# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all.to_a }
    redirect_to kitchen_root_path(kitchen_slug: @kitchens.first.slug) if @kitchens.size == 1
  end
end
