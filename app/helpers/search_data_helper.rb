# frozen_string_literal: true

# Builds a JSON blob of searchable recipe data for the client-side search
# overlay. Rendered once per page in the application layout. Returns a
# top-level object with all_tags, all_categories, recipes, ingredients, and
# custom_items keys so the overlay can offer tag/category pill filtering and
# fuzzy ingredient/grocery matching without a server round-trip.
#
# Trade-off: the full blob is embedded on every page for instant search with
# no server round-trip. Payload grows linearly with recipe count (~1KB per
# recipe). If it exceeds ~50KB, consider lazy-loading via fetch on overlay open.
#
# Collaborators:
# - ApplicationController (current_kitchen provides tenant scope)
# - search_overlay_controller.js (consumes the JSON in the browser)
module SearchDataHelper
  def search_data_json
    recipes = current_kitchen.recipes.includes(:category, :ingredients, :tags).alphabetical
    plan = MealPlan.for_kitchen(current_kitchen)

    {
      all_tags: current_kitchen.tags.order(:name).pluck(:name),
      all_categories: current_kitchen.categories.ordered.pluck(:name),
      recipes: recipes.map { |r| search_entry_for(r) },
      ingredients: ingredient_corpus(recipes, plan),
      custom_items: custom_item_corpus(plan)
    }.to_json
  end

  private

  def ingredient_corpus(recipes, plan)
    names = recipes.flat_map { |r| r.ingredients.map(&:name) }
    names.concat(plan.on_hand.keys)
    names.uniq.sort
  end

  def custom_item_corpus(plan)
    cutoff = Date.current - MealPlan::CUSTOM_ITEM_RETENTION
    plan.custom_items
        .select { |_, e| Date.parse(e['last_used_at']) >= cutoff }
        .map { |name, entry| { name:, aisle: entry['aisle'] } }
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
