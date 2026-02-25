# frozen_string_literal: true

class CrossReference < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :step, inverse_of: :cross_references
  belongs_to :target_recipe, class_name: 'Recipe', optional: true

  validates :position, presence: true, uniqueness: { scope: :step_id }
  validates :target_slug, presence: true
  validates :target_title, presence: true

  scope :pending, -> { where(target_recipe_id: nil) }
  scope :resolved, -> { where.not(target_recipe_id: nil) }

  def resolved? = target_recipe_id.present?
  def pending?  = !resolved?

  def expanded_ingredients
    return [] unless target_recipe

    target_recipe.own_ingredients_aggregated.map do |name, amounts|
      scaled = amounts.map { |amount| amount && Quantity[amount.value * multiplier, amount.unit] }
      [name, scaled]
    end
  end

  def self.resolve_pending(kitchen:)
    slugs = pending.distinct.pluck(:target_slug)
    return if slugs.empty?

    slug_to_id = kitchen.recipes.where(slug: slugs).pluck(:slug, :id).to_h
    return if slug_to_id.empty?

    pending.where(target_slug: slug_to_id.keys).find_each do |ref|
      ref.update_column(:target_recipe_id, slug_to_id.fetch(ref.target_slug)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
