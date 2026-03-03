# frozen_string_literal: true

# Owns ALL recipe-related Turbo Stream broadcasting. Public class-method entry
# points: `broadcast` (create/update), `broadcast_destroy`, `broadcast_rename`,
# `broadcast_recipe_selector`, `notify_recipe_deleted`. Broadcasts HTML replacements
# to every page showing recipe data (listings, selector, ingredients, recipe page)
# and cascades updates to cross-referencing parent recipes.
#
# - RecipeWriteService: sole caller for CRUD broadcasts
# - MealPlanBroadcaster: morphs grocery/menu pages after recipe changes
# - Turbo::StreamsChannel: transport layer for all stream pushes
class RecipeBroadcaster # rubocop:disable Metrics/ClassLength
  include IngredientRows

  SHOW_INCLUDES = [
    :category,
    { steps: [:ingredients, { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }] }
  ].freeze

  def self.broadcast(kitchen:, action:, recipe_title:, recipe: nil)
    new(kitchen).broadcast(action:, recipe_title:, recipe:)
  end

  def self.broadcast_recipe_selector(kitchen:, stream: 'recipes')
    new(kitchen).broadcast_recipe_selector(stream:)
  end

  def self.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
    notify_recipe_deleted(recipe, recipe_title:)
    broadcaster = new(kitchen)
    broadcaster.send(:update_referencing_recipes, parent_ids)
    broadcaster.broadcast(action: :deleted, recipe_title:)
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

  def self.broadcast_rename(old_recipe, new_title:, redirect_path:)
    Turbo::StreamsChannel.broadcast_replace_to(
      old_recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: old_recipe.title,
                redirect_path:,
                redirect_title: new_title }
    )
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def broadcast(action:, recipe_title:, recipe: nil)
    categories = preload_categories

    broadcast_recipe_listings(categories)
    broadcast_ingredients(categories.flat_map(&:recipes))
    broadcast_recipe_page(recipe, action:, recipe_title:)
    broadcast_toast(action:, recipe_title:)
    MealPlanBroadcaster.broadcast_all(kitchen)
  end

  def broadcast_recipe_selector(**)
    MealPlanBroadcaster.broadcast_menu_morph(kitchen)
  end

  private

  attr_reader :kitchen

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

  def update_referencing_recipes(parent_ids)
    return if parent_ids.empty?

    kitchen.recipes.where(id: parent_ids).includes(SHOW_INCLUDES).find_each do |parent|
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
end
