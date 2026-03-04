# frozen_string_literal: true

# Nutrition and grocery metadata for ingredients. Uses an overlay model: seed
# entries are global (kitchen_id: nil), kitchens can add overrides. lookup_for
# merges global + kitchen entries with kitchen taking precedence, then adds
# inflected name variants for fuzzy matching. Stores FDA-label nutrients,
# density (for volume-to-gram conversion), named portions, aisle assignments,
# and provenance sources.
#
# Collaborators:
# - FamilyRecipes::NutritionConstraints (shared validation rules)
# - NutritionCalculator and ShoppingListBuilder consume this.
class IngredientCatalog < ApplicationRecord
  self.table_name = 'ingredient_catalog'

  belongs_to :kitchen, optional: true

  NUTRIENT_COLUMNS = FamilyRecipes::NutritionConstraints::NUTRIENT_KEYS

  NUTRIENT_DISPLAY = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map do |d|
    label = d.indent.positive? ? "#{'  ' * d.indent}#{d.label}" : d.label
    [label, d.key, d.unit]
  end.freeze

  DENSITY_FIELDS = %i[density_grams density_volume density_unit].freeze
  private_constant :DENSITY_FIELDS

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, numericality: { greater_than: 0 }, allow_nil: true
  validates :aisle, length: { maximum: FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH }, allow_nil: true
  validate :nutrients_require_basis_grams
  validate :nutrient_values_in_range
  validate :density_completeness
  validate :portion_values_positive

  before_save :normalize_portion_keys

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  def assign_from_params(nutrients:, density:, portions:, aisle:, sources:, aliases: nil) # rubocop:disable Metrics/ParameterLists
    assign_nutrients(nutrients)
    assign_density(density)
    self.portions = normalize_portions_hash(portions)
    self.aisle = aisle if aisle
    self.sources = sources
    self.aliases = aliases unless aliases.nil?
  end

  def self.lookup_for(kitchen)
    base = global.index_by(&:ingredient_name)
                 .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
    add_ingredient_variants(base)
  end

  def self.resolver_for(kitchen)
    IngredientResolver.new(lookup_for(kitchen))
  end

  def self.attrs_from_yaml(entry)
    attrs = { aisle: entry['aisle'] }

    if (nutrients = entry['nutrients'])
      NUTRIENT_COLUMNS.each { |col| attrs[col] = nutrients[col.to_s] }
      attrs[:basis_grams] = nutrients['basis_grams']
    end

    if (density = entry['density'])
      attrs[:density_grams] = density['grams']
      attrs[:density_volume] = density['volume']
      attrs[:density_unit] = density['unit']
    end

    attrs[:aliases] = entry['aliases'] || []
    attrs[:portions] = entry['portions'] || {}
    attrs[:sources] = entry['sources'] || []

    attrs
  end

  def self.add_ingredient_variants(lookup)
    extras = lookup.each_value.with_object({}) do |entry, acc|
      FamilyRecipes::Inflector.ingredient_variants(entry.ingredient_name).each do |variant|
        acc[variant] = entry unless lookup.key?(variant)
      end
      add_alias_keys(acc, entry, lookup)
    end
    lookup.merge(extras)
  end

  def self.add_alias_keys(extras, entry, lookup)
    return if entry.aliases.blank?

    entry.aliases.each do |alias_name|
      lowered = alias_name.downcase
      next if lookup.key?(alias_name) || lookup.key?(lowered)

      alias_case_variants(alias_name).each { |v| extras[v] ||= entry }
      FamilyRecipes::Inflector.ingredient_variants(alias_name).each { |v| extras[v] ||= entry }
    end
  end

  # "AP flour" → ["AP flour", "ap flour", "AP Flour"]
  def self.alias_case_variants(name)
    capped = name.gsub(/\b(\w)/) { ::Regexp.last_match(1).upcase }
    [name, name.downcase, capped].uniq
  end
  private_class_method :add_ingredient_variants, :add_alias_keys, :alias_case_variants

  private

  def assign_nutrients(nutrients)
    return if nutrients.blank?

    allowed = nutrients.slice(:basis_grams, *NUTRIENT_COLUMNS)
    assign_attributes(allowed.transform_values(&:presence))
  end

  def assign_density(density)
    vals = density.present? && density.values.any?(&:present?) ? density : {}
    assign_attributes(density_volume: vals[:volume], density_unit: vals[:unit], density_grams: vals[:grams])
  end

  def normalize_portions_hash(raw)
    return {} if raw.blank?

    hash = raw.to_h.stringify_keys
    unitless_value = hash.delete('each') || hash.delete('Each')
    hash['~unitless'] = unitless_value if unitless_value
    hash
  end

  def normalize_portion_keys
    self.portions = normalize_portions_hash(portions)
  end

  def nutrients_require_basis_grams
    return if basis_grams.present?
    return unless NUTRIENT_COLUMNS.any? { |col| public_send(col).present? }

    errors.add(:basis_grams, 'is required when nutrient values are present')
  end

  def nutrient_values_in_range
    NUTRIENT_COLUMNS.each do |col|
      value = public_send(col)
      next unless value

      valid, msg = FamilyRecipes::NutritionConstraints.valid_nutrient?(col, value)
      errors.add(col, msg) unless valid
    end
  end

  def density_completeness
    present = DENSITY_FIELDS.select { |f| public_send(f).present? }
    return if present.empty? || present.size == DENSITY_FIELDS.size

    missing = DENSITY_FIELDS - present
    missing.each { |f| errors.add(f, 'is required when other density fields are set') }
  end

  def portion_values_positive
    return if portions.blank?

    portions.each do |name, value|
      valid, = FamilyRecipes::NutritionConstraints.valid_portion_value?(value.to_f)
      errors.add(:portions, "value for '#{name}' must be greater than 0") unless valid
    end
  end
end
