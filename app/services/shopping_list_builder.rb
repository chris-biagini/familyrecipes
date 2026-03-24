# frozen_string_literal: true

# Produces the grocery shopping list from a MealPlan's selected recipes and quick
# bites. Aggregates ingredient quantities (via IngredientAggregator), canonicalizes
# names through IngredientResolver, organizes items by grocery aisle, appends custom
# items, and sorts aisles by the kitchen's user-defined order. The lightweight
# `visible_names` method is used by write services for meal plan reconciliation
# without invoking `build`. Consumed by GroceriesController#show and MealPlanActions.
#
# Collaborators:
# - IngredientResolver — name canonicalization and catalog lookups
# - IngredientAggregator — quantity merging
# - IngredientCatalog.resolver_for — factory for resolver
class ShoppingListBuilder # rubocop:disable Metrics/ClassLength
  AISLE_SORT_PRIORITY = { ordered: 0, unordered: 1, miscellaneous: 2 }.freeze

  def self.visible_names_for(kitchen:, resolver: nil)
    new(kitchen:, resolver:).visible_names
  end

  def initialize(kitchen:, meal_plan: nil, resolver: nil)
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

  def visible_names
    custom = visible_custom_item_names.map { |name| canonical_name(name) }
    (canonical_recipe_names + canonical_quick_bite_names + custom)
      .reject { |name| @resolver.omitted?(name) }.to_set
  end

  private

  def canonical_recipe_names
    selected_recipes.flat_map { |r| r.all_ingredients_with_quantities.map(&:first) }
                    .map { |name| canonical_name(name) }
  end

  def canonical_quick_bite_names
    selected_quick_bites.flat_map { |qb| qb.ingredients_with_quantities.map(&:first) }
                        .map { |name| canonical_name(name) }
  end

  def merge_all_ingredients
    recipe_ingredients = aggregate_recipe_ingredients
    quick_bite_ingredients = aggregate_quick_bite_ingredients

    recipe_ingredients.merge(quick_bite_ingredients) do |_name, existing, incoming|
      merge_entries(existing, incoming)
    end
  end

  def merge_entries(existing, incoming)
    {
      amounts: merge_clean_amounts(existing[:amounts], incoming[:amounts]),
      sources: (existing[:sources] + incoming[:sources]).uniq,
      uncounted: existing[:uncounted] + incoming[:uncounted]
    }
  end

  def selected_recipes
    slugs = @meal_plan ? @meal_plan.selected_recipes : MealPlanSelection.recipe_slugs_for(@kitchen)
    @kitchen.recipes.with_full_tree.where(slug: slugs)
  end

  def selected_quick_bites
    ids = @meal_plan ? @meal_plan.selected_quick_bites : MealPlanSelection.quick_bite_ids_for(@kitchen)
    return [] if ids.empty?

    @kitchen.parsed_quick_bites.select { |qb| ids.include?(qb.id) }
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
    uncounted = amounts.count(nil)
    clean = amounts.compact

    if merged.key?(key)
      merge_into_existing(merged[key], clean, uncounted, source)
    else
      merged[key] = { amounts: clean, sources: [source], uncounted: uncounted }
    end
  end

  def merge_into_existing(entry, clean_amounts, uncounted, source)
    entry[:amounts] = merge_clean_amounts(entry[:amounts], clean_amounts)
    entry[:sources] = (entry[:sources] + [source]).uniq
    entry[:uncounted] += uncounted
  end

  def merge_clean_amounts(existing, incoming)
    return existing if incoming.empty?
    return incoming if existing.empty?

    IngredientAggregator.merge_amounts(existing, incoming)
  end

  def visible_custom_item_names
    if @meal_plan
      @meal_plan.visible_custom_items.keys
    else
      CustomGroceryItem.where(kitchen_id: @kitchen.id).visible.pluck(:name)
    end
  end

  def custom_items_from_ar
    CustomGroceryItem.where(kitchen_id: @kitchen.id).visible.each_with_object({}) do |item, hash|
      hash[item.name] = { 'aisle' => item.aisle }
    end
  end

  def canonical_name(name)
    @resolver.resolve(name)
  end

  def organize_by_aisle(ingredients)
    visible = ingredients.reject { |name, _| @resolver.omitted?(name) }
    grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, entry), result|
      result[aisle_for(name)] << {
        name: name, amounts: serialize_amounts(entry[:amounts]),
        sources: entry[:sources], uncounted: entry[:uncounted]
      }
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
    custom = @meal_plan ? @meal_plan.visible_custom_items : custom_items_from_ar
    return if custom.empty?

    existing = existing_canonical_names(organized)
    new_items = custom.filter_map { |name, entry| custom_item_entry_from_hash(name, entry, organized, existing) }
    return if new_items.empty?

    new_items.each { |aisle, item| (organized[aisle] ||= []) << item }
    organized.replace(sort_aisles(organized))
  end

  def custom_item_entry_from_hash(name, entry, organized, existing)
    canonical = canonical_name(name)
    return if existing.include?(canonical)

    aisle = resolve_aisle_hint(entry['aisle'], organized)
    [aisle, { name: canonical, amounts: [], sources: [], uncounted: 0 }]
  end

  def resolve_aisle_hint(hint, organized)
    match = organized.keys.find { |k| k.casecmp(hint).zero? }
    return match if match

    order_match = @kitchen.parsed_aisle_order.find { |a| a.casecmp(hint).zero? }
    order_match || hint
  end

  def existing_canonical_names(organized)
    organized.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
  end

  def serialize_amounts(amounts)
    amounts.map { |q| [q.value.to_f, display_unit(q)] }
  end

  def display_unit(quantity)
    return quantity.unit unless quantity.unit

    FamilyRecipes::Inflector.unit_display(quantity.unit, quantity.value)
  end
end
