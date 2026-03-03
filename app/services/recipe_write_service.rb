# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), clean up
# orphan categories, and prune stale meal plan entries. All Turbo broadcasting
# is delegated to RecipeBroadcaster. Controllers validate input and render
# responses; this service owns domain orchestration.
#
# - MarkdownImporter: parses markdown into AR records
# - RecipeBroadcaster: all real-time Turbo Stream updates
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
    RecipeBroadcaster.broadcast(kitchen:, action: :created, recipe_title: recipe.title, recipe:)
    post_write_cleanup
    Result.new(recipe:, updated_references: [])
  end

  def update(slug:, markdown:)
    old_recipe = kitchen.recipes.find_by!(slug:)
    recipe = import_and_timestamp(markdown)
    updated_references = rename_cross_references(old_recipe, recipe)
    handle_slug_change(old_recipe, recipe)
    RecipeBroadcaster.broadcast(kitchen:, action: :updated, recipe_title: recipe.title, recipe:)
    post_write_cleanup
    Result.new(recipe:, updated_references:)
  end

  def destroy(slug:)
    recipe = kitchen.recipes.find_by!(slug:)
    parent_ids = recipe.referencing_recipes.pluck(:id)
    recipe.destroy!
    RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title: recipe.title, parent_ids:)
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
    MealPlan.prune_stale_items(kitchen:)
  end
end
