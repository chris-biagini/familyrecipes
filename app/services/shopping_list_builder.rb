# frozen_string_literal: true

class ShoppingListBuilder
  def initialize(kitchen:, grocery_list:)
    @kitchen = kitchen
    @grocery_list = grocery_list
    @profiles = IngredientCatalog.lookup_for(kitchen)
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

    quick_bite_ingredients.each do |name, amounts|
      recipe_ingredients[name] =
        recipe_ingredients.key?(name) ? merge_amounts(recipe_ingredients[name], amounts) : amounts
    end

    recipe_ingredients
  end

  def selected_recipes
    slugs = @grocery_list.state.fetch('selected_recipes', [])
    @kitchen.recipes.includes(:category, steps: :ingredients).where(slug: slugs)
  end

  def selected_quick_bites
    slugs = @grocery_list.state.fetch('selected_quick_bites', [])
    return [] if slugs.empty?

    content = @kitchen.quick_bites_content
    return [] unless content

    all_bites = FamilyRecipes.parse_quick_bites_content(content)
    all_bites.select { |qb| slugs.include?(qb.id) }
  end

  def aggregate_recipe_ingredients
    recipe_map = build_recipe_map

    selected_recipes.each_with_object({}) do |recipe, merged|
      parsed = recipe_map[recipe.slug]
      next unless parsed

      parsed.all_ingredients_with_quantities(recipe_map).each do |name, amounts|
        merged[name] = merged.key?(name) ? merge_amounts(merged[name], amounts) : amounts
      end
    end
  end

  def aggregate_quick_bite_ingredients
    selected_quick_bites.each_with_object({}) do |qb, merged|
      qb.ingredients_with_quantities.each do |name, amounts|
        merged[name] = merged.key?(name) ? merge_amounts(merged[name], amounts) : amounts
      end
    end
  end

  def build_recipe_map
    @kitchen.recipes.includes(:category, steps: :ingredients).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end

  def merge_amounts(existing, new_amounts)
    all = existing + new_amounts
    has_nil = all.include?(nil)

    sums = all.compact.each_with_object(Hash.new(0.0)) do |quantity, h|
      h[quantity.unit] += quantity.value
    end

    result = sums.map { |unit, value| Quantity[value, unit] }
    result << nil if has_nil
    result
  end

  def organize_by_aisle(ingredients)
    result = Hash.new { |h, k| h[k] = [] }

    ingredients.each do |name, amounts|
      aisle = @profiles[name]&.aisle
      next if aisle == 'omit'

      target_aisle = aisle || 'Miscellaneous'
      result[target_aisle] << { name: name, amounts: serialize_amounts(amounts) }
    end

    result.sort_by { |aisle, _| aisle == 'Miscellaneous' ? 'zzz' : aisle }.to_h
  end

  def add_custom_items(organized)
    custom = @grocery_list.state.fetch('custom_items', [])
    return if custom.empty?

    organized['Miscellaneous'] ||= []
    custom.each { |item| organized['Miscellaneous'] << { name: item, amounts: [] } }
  end

  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value, q.unit] }
  end
end
