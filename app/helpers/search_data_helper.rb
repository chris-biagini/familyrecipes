# frozen_string_literal: true

# Builds a JSON blob of searchable recipe data for the client-side search
# overlay. Rendered once per page in the application layout. Returns a
# top-level object with all_tags, all_categories, recipes, ingredients, and
# custom_items keys so the overlay can offer tag/category pill filtering and
# fuzzy ingredient/grocery matching without a server round-trip.
#
# Trade-off: the full blob is embedded on every page for instant search with
# no server round-trip. Payload grows linearly with recipe count (~250 bytes
# per recipe). If it exceeds ~50KB, consider lazy-loading via fetch on overlay
# open. Cached per-kitchen keyed on updated_at; invalidated by
# Kitchen.finalize_writes (which touches the kitchen).
#
# Collaborators:
# - ApplicationController (current_kitchen provides tenant scope)
# - search_overlay_controller.js (consumes the JSON in the browser)
module SearchDataHelper
  def search_data_json
    Rails.cache.fetch(search_data_cache_key) { build_search_data_json }
  end

  private

  def search_data_cache_key
    ['search_data', current_kitchen.id, current_kitchen.updated_at.to_f]
  end

  def build_search_data_json
    recipes = current_kitchen.recipes.includes(:category, :ingredients, :tags).alphabetical

    {
      all_tags: current_kitchen.tags.order(:name).pluck(:name),
      all_categories: current_kitchen.categories.ordered.pluck(:name),
      recipes: recipes.map { |r| search_entry_for(r) },
      ingredients: ingredient_corpus(recipes),
      custom_items: custom_item_corpus
    }.to_json
  end

  def ingredient_corpus(recipes)
    names = recipes.flat_map { |r| r.ingredients.map(&:name) }
    names.concat(OnHandEntry.where(kitchen_id: current_kitchen.id).pluck(:ingredient_name))
    names.concat(current_kitchen.quick_bites.joins(:quick_bite_ingredients).pluck('quick_bite_ingredients.name'))
    names.uniq.sort
  end

  def custom_item_corpus
    CustomGroceryItem.where(kitchen_id: current_kitchen.id).visible.pluck(:name, :aisle)
                     .map { |name, aisle| { name:, aisle: } }
  end

  def search_entry_for(recipe)
    {
      title: recipe.title,
      slug: recipe.slug,
      description: recipe.description.to_s,
      category: recipe.category.name,
      tags: recipe.tags.map(&:name).sort,
      ingredients: recipe.ingredients.map(&:name).uniq
    }
  end
end
