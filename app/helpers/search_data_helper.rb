# frozen_string_literal: true

# Builds a JSON blob of searchable recipe data for the client-side search
# overlay. Rendered once per page in the application layout. The blob is small
# (well under 10KB even at 100 recipes) because it carries only the fields
# the search overlay needs: title, slug, description, category, ingredients.
#
# Collaborators:
# - ApplicationController (current_kitchen provides tenant scope)
# - search_overlay_controller.js (consumes the JSON in the browser)
module SearchDataHelper
  def search_data_json
    recipes = current_kitchen.recipes.includes(:category, :ingredients).alphabetical

    recipes.map { |recipe| search_entry_for(recipe) }.to_json
  end

  private

  def search_entry_for(recipe)
    {
      title: recipe.title,
      slug: recipe.slug,
      description: recipe.description.to_s,
      category: recipe.category.name,
      ingredients: recipe.ingredients.map(&:name).uniq
    }
  end
end
