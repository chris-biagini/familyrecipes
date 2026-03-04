# frozen_string_literal: true

# Computes per-recipe and per-quick-bite ingredient availability for the menu
# page's availability badges. For each recipe/quick bite, reports how many
# ingredients are still needed (not yet checked off on the grocery list). Used
# by MenuController for badge rendering.
#
# Collaborators:
# - IngredientResolver — name resolution (case-insensitive, variant collapsing)
# - IngredientCatalog.resolver_for — default resolver factory
# - MenuController — sole caller
class RecipeAvailabilityCalculator
  def initialize(kitchen:, checked_off:, resolver: nil)
    @kitchen = kitchen
    @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
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
    Set.new(@resolver.lookup.each_value.select { |p| p.aisle == 'omit' }.map(&:ingredient_name))
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
    @resolver.resolve(name)
  end

  def loaded_recipes
    @kitchen.recipes.with_full_tree
  end

  def quick_bites
    @kitchen.parsed_quick_bites
  end
end
