# frozen_string_literal: true

# Nutrition and grocery metadata for ingredients. Uses an overlay model: seed
# entries are global (kitchen_id: nil), kitchens can add overrides. lookup_for
# merges global + kitchen entries with kitchen taking precedence, then adds
# inflected name variants for fuzzy matching. Stores FDA-label nutrients,
# density (for volume-to-gram conversion), named portions, aisle assignments,
# and provenance sources. NutritionCalculator and ShoppingListBuilder consume this.
class IngredientCatalog < ApplicationRecord
  self.table_name = 'ingredient_catalog'

  belongs_to :kitchen, optional: true

  NUTRIENT_COLUMNS = %i[calories fat saturated_fat trans_fat cholesterol
                        sodium carbs fiber total_sugars added_sugars protein].freeze

  NUTRIENT_DISPLAY = [
    ['Calories',         :calories,      ''],
    ['Total Fat',        :fat,           'g'],
    ['  Saturated Fat',  :saturated_fat, 'g'],
    ['  Trans Fat',      :trans_fat,     'g'],
    ['Cholesterol',      :cholesterol,   'mg'],
    ['Sodium',           :sodium,        'mg'],
    ['Total Carbs',      :carbs,         'g'],
    ['  Dietary Fiber',  :fiber,         'g'],
    ['  Total Sugars',   :total_sugars,  'g'],
    ['    Added Sugars', :added_sugars,  'g'],
    ['Protein',          :protein,       'g']
  ].freeze

  DENSITY_FIELDS = %i[density_grams density_volume density_unit].freeze
  private_constant :DENSITY_FIELDS

  # Sodium is in mg and legitimately exceeds 10,000 per 100g (salt: ~38,758)
  NUTRIENT_MAX = Hash.new(10_000).merge(sodium: 50_000).freeze

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, numericality: { greater_than: 0 }, allow_nil: true
  validates :aisle, length: { maximum: Kitchen::MAX_AISLE_NAME_LENGTH }, allow_nil: true
  validate :nutrients_require_basis_grams
  validate :nutrient_values_in_range
  validate :density_completeness
  validate :portion_values_positive

  before_save :normalize_portion_keys

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  def assign_from_params(nutrients:, density:, portions:, aisle:, sources:)
    assign_nutrients(nutrients)
    assign_density(density)
    self.portions = normalize_portions_hash(portions)
    self.aisle = aisle if aisle
    self.sources = sources
  end

  def self.lookup_for(kitchen)
    base = global.index_by(&:ingredient_name)
                 .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
    add_ingredient_variants(base)
  end

  def self.add_ingredient_variants(lookup)
    variants = lookup.each_value.with_object({}) do |entry, acc|
      FamilyRecipes::Inflector.ingredient_variants(entry.ingredient_name).each do |variant|
        acc[variant] = entry unless lookup.key?(variant)
      end
    end
    lookup.merge(variants)
  end
  private_class_method :add_ingredient_variants

  private

  def assign_nutrients(nutrients)
    return if nutrients.blank?

    allowed = nutrients.slice(:basis_grams, *NUTRIENT_COLUMNS)
    assign_attributes(allowed.transform_values(&:presence))
  end

  def assign_density(density)
    if density.blank? || density.values.all?(&:blank?)
      assign_attributes(density_volume: nil, density_unit: nil, density_grams: nil)
    else
      assign_attributes(density_volume: density[:volume],
                        density_unit: density[:unit],
                        density_grams: density[:grams])
    end
  end

  def normalize_portions_hash(raw)
    return {} if raw.blank?

    hash = raw.to_h.stringify_keys
    unitless_value = hash.delete('each') || hash.delete('Each')
    hash['~unitless'] = unitless_value if unitless_value
    hash
  end

  def normalize_portion_keys
    return if portions.blank?

    unitless_value = portions.delete('each') || portions.delete('Each')
    portions['~unitless'] = unitless_value if unitless_value
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

      max = NUTRIENT_MAX[col]
      errors.add(col, "must be between 0 and #{max}") unless value.between?(0, max)
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
      errors.add(:portions, "value for '#{name}' must be greater than 0") unless value.to_f.positive?
    end
  end
end
