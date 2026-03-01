# frozen_string_literal: true

# Produces the grocery shopping list from a MealPlan's selected recipes and quick
# bites. Aggregates ingredient quantities (via IngredientAggregator), canonicalizes
# names through IngredientCatalog, organizes items by grocery aisle, appends custom
# items, and sorts aisles by the kitchen's user-defined order. Consumed by
# GroceriesController#state and MealPlan#prune_checked_off.
class ShoppingListBuilder
  def initialize(kitchen:, meal_plan:)
    @kitchen = kitchen
    @meal_plan = meal_plan
    @profiles = IngredientCatalog.lookup_for(kitchen)
    @profiles_ci = @profiles.transform_keys(&:downcase)
    @uncataloged_names = {}
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

    content = @kitchen.quick_bites_content
    return [] unless content

    all_bites = FamilyRecipes.parse_quick_bites_content(content)
    all_bites.select { |qb| slugs.include?(qb.id) }
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
    profile = @profiles[name] || @profiles_ci[name.downcase]
    return profile.ingredient_name if profile

    # For uncataloged ingredients, keep first-seen capitalization
    @uncataloged_names[name.downcase] ||= name
  end

  def organize_by_aisle(ingredients)
    visible = ingredients.reject { |name, _| @profiles[name]&.aisle == 'omit' }
    grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, entry), result|
      target_aisle = @profiles[name]&.aisle || 'Miscellaneous'
      result[target_aisle] << { name: name, amounts: serialize_amounts(entry[:amounts]), sources: entry[:sources] }
    end

    sort_aisles(grouped)
  end

  def sort_aisles(aisles_hash)
    order = @kitchen.parsed_aisle_order
    return aisles_hash.sort_by { |aisle, _| aisle == 'Miscellaneous' ? 'zzz' : aisle }.to_h if order.empty?

    aisles_hash.sort_by { |aisle, _| aisle_sort_key(aisle, order) }.to_h
  end

  def aisle_sort_key(aisle, order)
    position = order.index(aisle)
    return [0, position] if position

    # Miscellaneous defaults to last unless explicitly ordered
    return [2, 0] if aisle == 'Miscellaneous'

    # Unordered aisles sort alphabetically after ordered ones
    [1, aisle]
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
