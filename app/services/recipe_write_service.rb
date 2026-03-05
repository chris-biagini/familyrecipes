# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), clean up
# orphan categories, and prune stale meal plan entries. Triggers a page-refresh
# morph via Kitchen#broadcast_update after every mutation.
#
# - MarkdownImporter: parses markdown into AR records
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - RecipeBroadcaster: targeted delete notifications and rename redirects
# - CrossReferenceUpdater: renames cross-references on title change
class RecipeWriteService
  Result = Data.define(:recipe, :updated_references)

  def self.create(markdown:, kitchen:)
    new(kitchen:).create(markdown:)
  end

  def self.update(slug:, markdown:, kitchen:)
    new(kitchen:).update(slug:, markdown:)
  end

  def self.destroy(slug:, kitchen:)
    new(kitchen:).destroy(slug:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def create(markdown:)
    recipe = import_and_timestamp(markdown)
    kitchen.broadcast_update
    post_write_cleanup
    Result.new(recipe:, updated_references: [])
  end

  def update(slug:, markdown:)
    old_recipe = kitchen.recipes.find_by!(slug:)
    recipe = import_and_timestamp(markdown)
    updated_references = rename_cross_references(old_recipe, recipe)
    handle_slug_change(old_recipe, recipe)
    kitchen.broadcast_update
    post_write_cleanup
    Result.new(recipe:, updated_references:)
  end

  def destroy(slug:)
    recipe = kitchen.recipes.find_by!(slug:)
    RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
    recipe.destroy!
    kitchen.broadcast_update
    post_write_cleanup
    Result.new(recipe:, updated_references: [])
  end

  private

  attr_reader :kitchen

  def import_and_timestamp(markdown)
    recipe = MarkdownImporter.import(markdown, kitchen:)
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

  def post_write_cleanup
    Category.cleanup_orphans(kitchen)
    prune_stale_meal_plan_items
  end

  def prune_stale_meal_plan_items
    plan = MealPlan.for_kitchen(kitchen)
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
  end
end
