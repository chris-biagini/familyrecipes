# frozen_string_literal: true

# Produces the grocery shopping list from a MealPlan's selected recipes and quick
# bites. Aggregates ingredient quantities (via IngredientAggregator), canonicalizes
# names through IngredientResolver, organizes items by grocery aisle, appends custom
# items, and sorts aisles by the kitchen's user-defined order. Consumed by
# GroceriesController#show and MealPlan.prune_stale_items.
#
# Collaborators:
# - IngredientResolver — name canonicalization and catalog lookups
# - IngredientAggregator — quantity merging
# - IngredientCatalog.resolver_for — factory for resolver
class ShoppingListBuilder
  AISLE_SORT_PRIORITY = { ordered: 0, unordered: 1, miscellaneous: 2 }.freeze

  def initialize(kitchen:, meal_plan:, resolver: nil)
    @kitchen = kitchen
    @meal_plan = meal_plan
    @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
  end

  def build
    ingredients = merge_all_ingredients
    organized = organize_by_aisle(ingredients)
    add_custom_items(organized)
    organized
  end

  private

  def merge_all_ingredients
    recipe_ingredients = aggregate_recipe_ingredients
    quick_bite_ingredients = aggregate_quick_bite_ingredients

    recipe_ingredients.merge(quick_bite_ingredients) do |_name, existing, incoming|
      merge_entries(existing, incoming)
    end
  end

  def merge_entries(existing, incoming)
    {
      amounts: IngredientAggregator.merge_amounts(existing[:amounts], incoming[:amounts]),
      sources: (existing[:sources] + incoming[:sources]).uniq
    }
  end

  def selected_recipes
    slugs = @meal_plan.state.fetch('selected_recipes', [])
    xref_includes = { cross_references: { target_recipe: { steps: :ingredients } } }
    @kitchen.recipes
            .includes(:category, steps: [:ingredients, xref_includes])
            .where(slug: slugs)
  end

  def selected_quick_bites
    slugs = @meal_plan.state.fetch('selected_quick_bites', [])
    return [] if slugs.empty?

    @kitchen.parsed_quick_bites.select { |qb| slugs.include?(qb.id) }
  end

  def aggregate_recipe_ingredients
    selected_recipes.each_with_object({}) do |recipe, merged|
      recipe.all_ingredients_with_quantities.each do |name, amounts|
        merge_ingredient(merged, name, amounts, source: recipe.title)
      end
    end
  end

  def aggregate_quick_bite_ingredients
    selected_quick_bites.each_with_object({}) do |qb, merged|
      qb.ingredients_with_quantities.each do |name, amounts|
        merge_ingredient(merged, name, amounts, source: qb.title)
      end
    end
  end

  def merge_ingredient(merged, name, amounts, source:)
    key = canonical_name(name)
    entry = { amounts: amounts, sources: [source] }
    merged[key] = merged.key?(key) ? merge_entries(merged[key], entry) : entry
  end

  def canonical_name(name)
    @resolver.resolve(name)
  end

  def organize_by_aisle(ingredients)
    visible = ingredients.reject { |name, _| aisle_for(name) == 'omit' }
    grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, entry), result|
      result[aisle_for(name)] << { name: name, amounts: serialize_amounts(entry[:amounts]), sources: entry[:sources] }
    end

    sort_aisles(grouped)
  end

  def aisle_for(name)
    @resolver.catalog_entry(name)&.aisle || 'Miscellaneous'
  end

  def sort_aisles(aisles_hash)
    order = @kitchen.parsed_aisle_order
    aisles_hash.sort_by { |aisle, _| aisle_sort_key(aisle, order) }.to_h
  end

  def aisle_sort_key(aisle, order)
    position = order.index(aisle)
    return [AISLE_SORT_PRIORITY[:ordered], position] if position

    # Miscellaneous defaults to last unless explicitly ordered
    return [AISLE_SORT_PRIORITY[:miscellaneous], 0] if aisle == 'Miscellaneous'

    [AISLE_SORT_PRIORITY[:unordered], aisle]
  end

  def add_custom_items(organized)
    custom = @meal_plan.state.fetch('custom_items', [])
    return if custom.empty?

    organized['Miscellaneous'] ||= []
    organized['Miscellaneous'].concat(custom.map { |item| { name: item, amounts: [], sources: [] } })
  end

  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value.to_f, display_unit(q)] }
  end

  def display_unit(quantity)
    return quantity.unit unless quantity.unit

    FamilyRecipes::Inflector.unit_display(quantity.unit, quantity.value)
  end
end
