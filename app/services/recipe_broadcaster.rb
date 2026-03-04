# frozen_string_literal: true

# Owns all recipe-related Turbo Stream broadcasting: listings, ingredient tables,
# recipe pages, and cascading updates to cross-referencing parents. Wraps queries
# in ActsAsTenant.with_tenant since callers may lack controller tenant context.
# Also triggers a meal-plan page-refresh so groceries/menu pages stay in sync.
#
# - RecipeWriteService: sole caller for CRUD broadcasts
# - Turbo::StreamsChannel: transport layer for all stream pushes
class RecipeBroadcaster
  include IngredientRows

  SHOW_INCLUDES = [
    :category,
    { steps: [:ingredients, { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }] }
  ].freeze

  def self.broadcast(kitchen:, action:, recipe_title:, recipe: nil)
    new(kitchen).broadcast(action:, recipe_title:, recipe:)
  end

  def self.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
    notify_recipe_deleted(recipe, recipe_title:)
    new(kitchen).broadcast_destroy(parent_ids:, recipe_title:)
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
    ActsAsTenant.with_tenant(kitchen) do
      catalog_lookup = IngredientCatalog.lookup_for(kitchen)
      categories = preload_categories

      broadcast_recipe_listings(categories)
      broadcast_ingredients(categories.flat_map(&:recipes), catalog_lookup:)
      broadcast_recipe_page(recipe, action:, recipe_title:)
      append_toast([kitchen, 'recipes'], "#{recipe_title} was #{action}")
      Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
    end
  end

  def broadcast_destroy(parent_ids:, recipe_title:)
    ActsAsTenant.with_tenant(kitchen) do
      update_referencing_recipes(parent_ids)
      broadcast(action: :deleted, recipe_title:)
    end
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

  def broadcast_ingredients(recipes, catalog_lookup:)
    rows = build_ingredient_rows(catalog_lookup, recipes:)
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

    message = "#{recipe_title} was #{action}"
    append_toast([recipe, 'content'], message)

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

  def append_toast(stream, message)
    Turbo::StreamsChannel.broadcast_append_to(
      *stream, target: 'notifications', partial: 'shared/toast', locals: { message: }
    )
  end
end
