# frozen_string_literal: true

# Computes per-recipe and per-quick-bite ingredient availability for the menu
# page's "availability dots." For each recipe/quick bite, reports how many
# ingredients are still needed (not yet checked off on the grocery list). Used
# by MenuController#state to provide real-time availability data.
class RecipeAvailabilityCalculator
  def initialize(kitchen:, checked_off:)
    @kitchen = kitchen
    @profiles = IngredientCatalog.lookup_for(kitchen)
    @checked_off = Set.new(checked_off.map { |name| canonical_name(name) })
    @omitted = build_omit_set
  end

  def call
    availability = recipe_availability
    availability.merge!(quick_bite_availability)
    availability
  end

  private

  def build_omit_set
    Set.new(@profiles.each_value.select { |p| p.aisle == 'omit' }.map(&:ingredient_name))
  end

  def recipe_availability
    loaded_recipes.each_with_object({}) do |recipe, result|
      needed = needed_ingredients(recipe.all_ingredients_with_quantities.map(&:first))
      result[recipe.slug] = availability_entry(needed)
    end
  end

  def quick_bite_availability
    quick_bites.each_with_object({}) do |qb, result|
      needed = needed_ingredients(qb.all_ingredient_names)
      result[qb.id] = availability_entry(needed)
    end
  end

  def availability_entry(needed)
    missing = needed.reject { |name| @checked_off.include?(name) }
    { missing: missing.size, missing_names: missing, ingredients: needed }
  end

  def needed_ingredients(names)
    names.map { |name| canonical_name(name) }
         .reject { |name| @omitted.include?(name) }
         .uniq
  end

  def canonical_name(name)
    @profiles[name]&.ingredient_name || name
  end

  def loaded_recipes
    xref_includes = { cross_references: { target_recipe: { steps: :ingredients } } }
    @kitchen.recipes.includes(:category, steps: [:ingredients, xref_includes])
  end

  def quick_bites
    content = @kitchen.quick_bites_content
    return [] unless content

    FamilyRecipes.parse_quick_bites_content(content)
  end
end
