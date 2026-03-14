# frozen_string_literal: true

# Persistent recipe record, populated by MarkdownImporter from parsed Markdown.
# Stores the original markdown_source plus pre-computed data (nutrition_data JSON,
# processed instructions with scalable number markup). Views render entirely from
# this model and its associations — the parser is never invoked on the read path.
# Kitchen-scoped via acts_as_tenant.
#
# Collaborators:
# - RecipeWriteService (sole write-path orchestrator for web operations)
# - RecipeNutritionJob / CascadeNutritionJob (async nutrition recomputation)
# - RecipeBroadcaster (delete/rename notifications on per-recipe streams)
# - IngredientAggregator (quantity merging for all_ingredients_with_quantities)
# - Tag / RecipeTag (kitchen-scoped labels, synced by RecipeWriteService)
class Recipe < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :category

  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps
  has_many :cross_references, through: :steps, strict_loading: true
  has_many :inbound_cross_references, class_name: 'CrossReference',
                                      foreign_key: :target_recipe_id,
                                      inverse_of: :target_recipe,
                                      dependent: :nullify
  has_many :recipe_tags, dependent: :destroy
  has_many :tags, through: :recipe_tags

  def referencing_recipes
    Recipe.where(id: inbound_cross_references.joins(:step).select('steps.recipe_id')).distinct
  end

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }
  validates :markdown_source, presence: true

  scope :alphabetical, -> { order(:title) }
  scope :with_full_tree, lambda {
    includes(:category, :tags,
             steps: [:ingredients,
                     { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }])
  }

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  def own_ingredients_aggregated
    ingredients.group_by(&:name).transform_values do |group|
      IngredientAggregator.aggregate_amounts(group)
    end
  end

  # Accepts optional _recipe_map for duck-typing parity with FamilyRecipes::Recipe,
  # which needs a recipe_map to resolve cross-references from parsed objects.
  # Accesses cross-references via steps (not the through-association) so callers'
  # preloading of steps: { cross_references: ... } is honored.
  def all_ingredients_with_quantities(_recipe_map = nil)
    steps.flat_map(&:cross_references).each_with_object(own_ingredients_aggregated) do |xref, merged|
      xref.expanded_ingredients.each do |name, amounts|
        merged[name] = merged.key?(name) ? IngredientAggregator.merge_amounts(merged[name], amounts) : amounts
      end
    end.to_a
  end

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(title)
end
