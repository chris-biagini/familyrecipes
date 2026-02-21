# frozen_string_literal: true

class RecipesController < ApplicationController
  def show
    recipe = RecipeFinder.find_by_slug(params[:id])

    if recipe
      render html: RecipeRenderer.render_html(recipe).html_safe
    else
      head :not_found
    end
  end
end
