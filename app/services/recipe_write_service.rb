# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), clean up
# orphan categories, and reconcile stale meal plan entries. The `finalize` step
# always cleans orphan categories but skips reconcile and broadcast when
# Kitchen.batching? is true (batch caller handles those once at the end).
#
# - MarkdownImporter: parses markdown into AR records
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - RecipeBroadcaster: targeted delete notifications and rename redirects
# - CrossReferenceUpdater: renames cross-references on title change
# - MealPlan#reconcile!: prunes stale selections and checked-off items
class RecipeWriteService
  Result = Data.define(:recipe, :updated_references)

  def self.create(markdown:, kitchen:, category_name: 'Miscellaneous')
    new(kitchen:).create(markdown:, category_name:)
  end

  def self.update(slug:, markdown:, kitchen:, category_name: 'Miscellaneous')
    new(kitchen:).update(slug:, markdown:, category_name:)
  end

  def self.destroy(slug:, kitchen:)
    new(kitchen:).destroy(slug:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def create(markdown:, category_name:)
    category = find_or_create_category(category_name)
    recipe = import_and_timestamp(markdown, category:)
    finalize
    Result.new(recipe:, updated_references: [])
  end

  def update(slug:, markdown:, category_name:)
    old_recipe = kitchen.recipes.find_by!(slug:)
    category = find_or_create_category(category_name)
    recipe = import_and_timestamp(markdown, category:)
    updated_references = rename_cross_references(old_recipe, recipe)
    handle_slug_change(old_recipe, recipe)
    finalize
    Result.new(recipe:, updated_references:)
  end

  def destroy(slug:)
    recipe = kitchen.recipes.find_by!(slug:)
    RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
    recipe.destroy!
    finalize
    Result.new(recipe:, updated_references: [])
  end

  private

  attr_reader :kitchen

  def find_or_create_category(name)
    name = 'Miscellaneous' if name.blank?
    slug = FamilyRecipes.slugify(name)
    kitchen.categories.find_or_create_by!(slug:) do |cat|
      cat.name = name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def import_and_timestamp(markdown, category:)
    recipe = MarkdownImporter.import(markdown, kitchen:, category:)
    recipe.update!(edited_at: Time.current)
    recipe
  end

  def rename_cross_references(old_recipe, new_recipe)
    return [] if old_recipe.title == new_recipe.title

    CrossReferenceUpdater.rename_references(
      old_title: old_recipe.title, new_title: new_recipe.title, kitchen:
    )
  end

  def handle_slug_change(old_recipe, new_recipe)
    return if new_recipe.slug == old_recipe.slug

    RecipeBroadcaster.broadcast_rename(
      old_recipe, new_title: new_recipe.title,
                  redirect_path: Rails.application.routes.url_helpers.recipe_path(new_recipe)
    )
    old_recipe.destroy!
  end

  def finalize
    Category.cleanup_orphans(kitchen)
    return if Kitchen.batching?

    prune_stale_meal_plan_items
    kitchen.broadcast_update
  end

  def prune_stale_meal_plan_items
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { plan.reconcile! }
  end
end
