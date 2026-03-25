# frozen_string_literal: true

# Produces the grocery shopping list from selected recipes, quick bites, and
# custom items stored as normalized AR records. Aggregates ingredient quantities
# (via IngredientAggregator), canonicalizes names through IngredientResolver,
# organizes items by grocery aisle, and sorts aisles by the kitchen's user-defined
# order. The lightweight `visible_names` method is used by write services for
# on-hand reconciliation without invoking `build`.
#
# Collaborators:
# - MealPlanSelection — which recipes/quick bites are selected
# - QuickBite / QuickBiteIngredient — AR-backed grocery bundles
# - CustomGroceryItem — user-added non-recipe grocery items
# - IngredientResolver — name canonicalization and catalog lookups
# - IngredientAggregator — quantity merging
class ShoppingListBuilder # rubocop:disable Metrics/ClassLength
  AISLE_SORT_PRIORITY = { ordered: 0, unordered: 1, miscellaneous: 2 }.freeze

  def self.visible_names_for(kitchen:, resolver: nil)
    new(kitchen:, resolver:).visible_names
  end

  def initialize(kitchen:, resolver: nil)
    @kitchen = kitchen
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
    slugs = MealPlanSelection.recipe_slugs_for(@kitchen)
    @kitchen.recipes.with_full_tree.where(slug: slugs)
  end

  def selected_quick_bites
    ids = MealPlanSelection.quick_bite_ids_for(@kitchen)
    return [] if ids.empty?

    @kitchen.quick_bites.where(id: ids).includes(:quick_bite_ingredients)
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
    CustomGroceryItem.where(kitchen_id: @kitchen.id).visible.pluck(:name)
  end

  def visible_custom_items
    CustomGroceryItem.where(kitchen_id: @kitchen.id).visible
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
    items = visible_custom_items.to_a
    return if items.empty?

    existing = existing_canonical_names(organized)
    new_items = items.filter_map { |item| custom_item_entry(item, organized, existing) }
    return if new_items.empty?

    new_items.each { |aisle, entry| (organized[aisle] ||= []) << entry }
    organized.replace(sort_aisles(organized))
  end

  def custom_item_entry(item, organized, existing)
    canonical = canonical_name(item.name)
    return if existing.include?(canonical)

    aisle = resolve_aisle_hint(item.aisle, organized)
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
