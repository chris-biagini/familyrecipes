# frozen_string_literal: true

class LandingController < ApplicationController
  def show
    @kitchens = Kitchen.all
  end
end
