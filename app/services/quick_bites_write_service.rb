# frozen_string_literal: true

# Orchestrates quick bites content updates. Owns persistence to
# Kitchen#quick_bites_content, parse validation (returning warnings),
# meal plan reconciliation, and broadcast. Parallels RecipeWriteService
# and CatalogWriteService — controllers call class methods, never
# inline post-save logic.
#
# - Kitchen#quick_bites_content: raw markdown storage
# - FamilyRecipes.parse_quick_bites_content: parser returning warnings
# - MealPlan#reconcile!: prunes stale selections after content changes
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end

  def self.update_from_structure(kitchen:, structure:)
    content = FamilyRecipes::QuickBitesSerializer.serialize(structure)
    new(kitchen:).update(content:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(content:)
    stored = content.to_s.presence
    warnings = parse_warnings(stored)
    kitchen.update!(quick_bites_content: stored)
    finalize
    Result.new(warnings:)
  end

  private

  attr_reader :kitchen

  def parse_warnings(content)
    return [] unless content

    FamilyRecipes.parse_quick_bites_content(content).warnings
  end

  def finalize
    return if Kitchen.batching?

    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry do
      visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
      plan.reconcile!(visible_names: visible)
    end
    kitchen.broadcast_update
  end
end
