# frozen_string_literal: true

class RecipesController < ApplicationController
  layout false

  def show
    @recipe = RecipeFinder.find_by_slug(params[:id])

    if @recipe
      render :show
    else
      head :not_found
    end
  end
end
