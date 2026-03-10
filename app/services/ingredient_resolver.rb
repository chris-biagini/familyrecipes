# frozen_string_literal: true

# Single source of truth for resolving ingredient names to their canonical form
# and for omit-from-shopping knowledge. Wraps an IngredientCatalog lookup hash
# with a three-step cascade: exact match, case-insensitive fallback, and
# uncataloged variant collapsing via Inflector. Stateful within a request —
# accumulates uncataloged names so that differently-cased or inflected forms of
# the same unknown ingredient collapse to one canonical name.
#
# Collaborators:
# - IngredientCatalog.resolver_for(kitchen) — factory entry point
# - ShoppingListBuilder, RecipeAvailabilityCalculator, IngredientRowBuilder — consumers
# - RecipeNutritionJob — uses omit_set for nutrition calculations
# - FamilyRecipes::Inflector — variant generation for uncataloged fallback
class IngredientResolver
  attr_reader :lookup

  def initialize(lookup)
    @lookup = lookup
    @ci_lookup = lookup.each_with_object({}) { |(k, v), h| h[k.downcase] ||= v }
    @uncataloged = {}
  end

  def resolve(name)
    entry = find_entry(name)
    return entry.ingredient_name if entry

    resolve_uncataloged(name)
  end

  def catalog_entry(name)
    find_entry(name)
  end

  def cataloged?(name)
    find_entry(name).present?
  end

  def omitted?(name)
    find_entry(name)&.omit_from_shopping == true
  end

  def omit_set
    @omit_set ||= @lookup.each_value
                         .select(&:omit_from_shopping)
                         .to_set { |e| e.ingredient_name.downcase }
  end

  def all_keys_for(canonical_name)
    keys = @lookup.filter_map { |raw, entry| raw if entry.ingredient_name == canonical_name }
    keys.push(canonical_name) unless keys.include?(canonical_name)
    keys
  end

  private

  def find_entry(name)
    @lookup[name] || @ci_lookup[name.downcase]
  end

  def resolve_uncataloged(name)
    return name if name.blank?

    downcased = name.downcase
    return @uncataloged[downcased] if @uncataloged.key?(downcased)

    existing = find_variant_match(name)
    return existing if existing

    @uncataloged[downcased] = name
  end

  def find_variant_match(name)
    FamilyRecipes::Inflector.ingredient_variants(name).each do |variant|
      canonical = @uncataloged[variant.downcase]
      return register_alias(name, canonical) if canonical
    end
    nil
  end

  def register_alias(name, canonical)
    @uncataloged[name.downcase] = canonical
    canonical
  end
end
