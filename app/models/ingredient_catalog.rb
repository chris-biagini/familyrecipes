# frozen_string_literal: true

class IngredientCatalog < ApplicationRecord
  self.table_name = 'ingredient_catalog'

  belongs_to :kitchen, optional: true

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, numericality: { greater_than: 0 }, allow_nil: true

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

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
end
