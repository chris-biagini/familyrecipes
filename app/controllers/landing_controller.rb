# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all }
  end
end
