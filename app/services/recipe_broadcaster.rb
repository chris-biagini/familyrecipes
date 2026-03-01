# frozen_string_literal: true

# Bridges recipe CRUD events to real-time Turbo Stream updates. On create/update/
# destroy, broadcasts HTML replacements to every page that shows recipe data:
# homepage (recipe listings), menu (recipe selector), ingredients (table + summary
# bar), and the recipe page itself. When a recipe is updated, also cascades a
# content replacement to every recipe that embeds it via cross-reference (one
# level only). Also fires toast notifications and triggers
# MealPlanChannel.broadcast_content_changed to refresh grocery/menu state.
class RecipeBroadcaster
  include IngredientRows

  SHOW_INCLUDES = {
    steps: [:ingredients, { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }]
  }.freeze

  def self.broadcast(kitchen:, action:, recipe_title:, recipe: nil)
    new(kitchen).broadcast(action:, recipe_title:, recipe:)
  end

  def self.notify_recipe_deleted(recipe, recipe_title:)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: }
    )
    Turbo::StreamsChannel.broadcast_append_to(
      recipe, 'content',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was deleted" }
    )
  end

  def self.broadcast_rename(old_recipe, new_title:, new_slug:)
    Turbo::StreamsChannel.broadcast_replace_to(
      old_recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: old_recipe.title,
                redirect_path: "/recipes/#{new_slug}",
                redirect_title: new_title }
    )
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def broadcast(action:, recipe_title:, recipe: nil)
    categories = preload_categories

    broadcast_recipe_listings(categories)
    broadcast_recipe_selector(categories)
    broadcast_ingredients(categories.flat_map(&:recipes))
    broadcast_recipe_page(recipe, action:, recipe_title:)
    broadcast_toast(action:, recipe_title:)
    MealPlanChannel.broadcast_content_changed(kitchen)
  end

  private

  attr_reader :kitchen

  def current_kitchen = kitchen

  def preload_categories
    kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
  end

  def broadcast_recipe_listings(categories)
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-listings',
      partial: 'homepage/recipe_listings',
      locals: { categories: categories.reject { |c| c.recipes.empty? } }
    )
  end

  def broadcast_recipe_selector(categories)
    quick_bites = parse_quick_bites
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: { categories:, quick_bites_by_subsection: quick_bites }
    )
  end

  def broadcast_ingredients(recipes)
    lookup = IngredientCatalog.lookup_for(kitchen)
    rows = build_ingredient_rows(lookup, recipes:)
    summary = build_summary(rows)

    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'ingredients-summary',
      partial: 'ingredients/summary_bar',
      locals: { summary: }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'ingredients-table',
      partial: 'ingredients/table',
      locals: { ingredient_rows: rows }
    )
  end

  def broadcast_recipe_page(recipe, action:, recipe_title:)
    return unless recipe

    broadcast_recipe_updated(recipe)
    broadcast_recipe_toast(recipe, action:, recipe_title:)
  end

  def broadcast_recipe_updated(recipe)
    fresh = kitchen.recipes.includes(SHOW_INCLUDES).find_by(slug: recipe.slug)
    return unless fresh

    replace_recipe_content(fresh)
    broadcast_referencing_recipes(fresh)
  end

  def broadcast_referencing_recipes(recipe)
    recipe.referencing_recipes.includes(SHOW_INCLUDES).find_each do |parent|
      replace_recipe_content(parent)
    end
  end

  def replace_recipe_content(recipe)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/recipe_content',
      locals: { recipe:, nutrition: recipe.nutrition_data }
    )
  end

  def broadcast_toast(action:, recipe_title:)
    message = "#{recipe_title} was #{action}"
    append_toast([kitchen, 'recipes'], message)
  end

  def broadcast_recipe_toast(recipe, action:, recipe_title:)
    append_toast([recipe, 'content'], "#{recipe_title} was #{action}")
  end

  def append_toast(stream, message)
    Turbo::StreamsChannel.broadcast_append_to(
      *stream, target: 'notifications', partial: 'shared/toast', locals: { message: }
    )
  end

  def parse_quick_bites
    content = kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
