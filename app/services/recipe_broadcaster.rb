# frozen_string_literal: true

class RecipeBroadcaster
  include IngredientRows

  def self.broadcast(kitchen:, action:, recipe_title:, recipe: nil)
    new(kitchen).broadcast(action:, recipe_title:, recipe:)
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
    broadcast_recipe_listings
    broadcast_recipe_selector
    broadcast_ingredients
    broadcast_recipe_page(recipe, action:, recipe_title:)
    broadcast_toast(action:, recipe_title:)
    MealPlanChannel.broadcast_content_changed(kitchen)
  end

  private

  attr_reader :kitchen

  def current_kitchen = kitchen

  def broadcast_recipe_listings
    categories = kitchen.categories.ordered.includes(:recipes).reject { |c| c.recipes.empty? }
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-listings',
      partial: 'homepage/recipe_listings',
      locals: { categories: }
    )
  end

  def broadcast_recipe_selector
    categories = kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    quick_bites = parse_quick_bites
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: { categories:, quick_bites_by_subsection: quick_bites }
    )
  end

  def broadcast_ingredients
    lookup = IngredientCatalog.lookup_for(kitchen)
    rows = build_ingredient_rows(lookup)
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

    if action == :deleted
      broadcast_recipe_deleted(recipe, recipe_title:)
    else
      broadcast_recipe_updated(recipe)
    end
    broadcast_recipe_toast(recipe, action:, recipe_title:)
  end

  def broadcast_recipe_updated(recipe)
    fresh = kitchen.recipes
                   .includes(steps: [:ingredients, { cross_references: :target_recipe }])
                   .find_by(slug: recipe.slug)
    return unless fresh

    Turbo::StreamsChannel.broadcast_replace_to(
      fresh, 'content',
      target: 'recipe-content',
      partial: 'recipes/recipe_content',
      locals: { recipe: fresh, nutrition: fresh.nutrition_data }
    )
  end

  def broadcast_recipe_deleted(recipe, recipe_title:)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: }
    )
  end

  def broadcast_toast(action:, recipe_title:)
    Turbo::StreamsChannel.broadcast_append_to(
      kitchen, 'recipes',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was #{action}" }
    )
  end

  def broadcast_recipe_toast(recipe, action:, recipe_title:)
    Turbo::StreamsChannel.broadcast_append_to(
      recipe, 'content',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was #{action}" }
    )
  end

  def parse_quick_bites
    content = kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
