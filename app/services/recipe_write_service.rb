# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Dual entry: `create`/`update`
# accept raw Markdown; `create_from_structure`/`update_from_structure` accept
# IR hashes (from graphical editors) and serialize via MarkdownImporter. Owns
# the full post-write pipeline: import, tag sync, rename cascades, orphan
# cleanup (categories + tags), and meal plan reconciliation. The `finalize`
# step always cleans orphans but skips reconcile and broadcast when
# Kitchen.batching? is true (batch caller handles those once at the end).
#
# - MarkdownImporter: parses markdown / IR hashes into AR records
# - Tag: created inline during sync; orphans cleaned in finalize
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - RecipeBroadcaster: targeted delete notifications and rename redirects
# - CrossReferenceUpdater: renames cross-references on title change
# - MealPlan#reconcile!: prunes stale selections and checked-off items
class RecipeWriteService
  Result = Data.define(:recipe, :updated_references)

  def self.create(markdown:, kitchen:, category_name: nil, tags: nil)
    new(kitchen:).create(markdown:, category_name:, tags:)
  end

  def self.update(slug:, markdown:, kitchen:, category_name: nil, tags: nil)
    new(kitchen:).update(slug:, markdown:, category_name:, tags:)
  end

  def self.create_from_structure(structure:, kitchen:)
    new(kitchen:).create_from_structure(structure:)
  end

  def self.update_from_structure(slug:, structure:, kitchen:)
    new(kitchen:).update_from_structure(slug:, structure:)
  end

  def self.destroy(slug:, kitchen:)
    new(kitchen:).destroy(slug:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def create(markdown:, category_name: nil, tags: nil)
    recipe = nil
    front_matter_tags = nil

    ActiveRecord::Base.transaction do
      category = find_or_create_category(category_name)
      recipe, front_matter_tags = import_and_timestamp(markdown, category:)
      sync_tags(recipe, tags || front_matter_tags)
    end

    finalize
    Result.new(recipe:, updated_references: [])
  end

  def create_from_structure(structure:)
    recipe = nil

    ActiveRecord::Base.transaction do
      category = find_or_create_category(structure.dig(:front_matter, :category))
      recipe = import_structure_and_timestamp(structure, category:)
      sync_tags(recipe, structure.dig(:front_matter, :tags))
    end

    finalize
    Result.new(recipe:, updated_references: [])
  end

  def update(slug:, markdown:, category_name: nil, tags: nil)
    updated_references = []
    recipe = nil

    ActiveRecord::Base.transaction do
      old_recipe = kitchen.recipes.find_by!(slug:)
      category = find_or_create_category(category_name)
      recipe, front_matter_tags = import_and_timestamp(markdown, category:)
      sync_tags(recipe, tags || front_matter_tags)
      updated_references = rename_cross_references(old_recipe, recipe)
      handle_slug_change(old_recipe, recipe)
    end

    finalize
    Result.new(recipe:, updated_references:)
  end

  def update_from_structure(slug:, structure:)
    updated_references = []
    recipe = nil

    ActiveRecord::Base.transaction do
      old_recipe = kitchen.recipes.find_by!(slug:)
      category = find_or_create_category(structure.dig(:front_matter, :category))
      recipe = import_structure_and_timestamp(structure, category:)
      sync_tags(recipe, structure.dig(:front_matter, :tags))
      updated_references = rename_cross_references(old_recipe, recipe)
      handle_slug_change(old_recipe, recipe)
    end

    finalize
    Result.new(recipe:, updated_references:)
  end

  def destroy(slug:)
    recipe = nil

    ActiveRecord::Base.transaction do
      recipe = kitchen.recipes.find_by!(slug:)
      RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
      recipe.destroy!
    end

    finalize
    Result.new(recipe:, updated_references: [])
  end

  private

  attr_reader :kitchen

  def find_or_create_category(name)
    return nil if name.blank?

    Category.find_or_create_for(kitchen, name)
  end

  def import_and_timestamp(markdown, category:)
    result = MarkdownImporter.import(markdown, kitchen:, category:)
    result.recipe.update!(edited_at: Time.current)
    [result.recipe, result.front_matter_tags]
  end

  def import_structure_and_timestamp(structure, category:)
    result = MarkdownImporter.import_from_structure(structure, kitchen:, category:)
    result.recipe.update!(edited_at: Time.current)
    result.recipe
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
    Tag.cleanup_orphans(kitchen)
    return if Kitchen.batching?

    prune_stale_meal_plan_items
    kitchen.broadcast_update
  end

  def sync_tags(recipe, tags)
    return unless tags

    desired = tags.map { |n| kitchen.tags.find_or_create_by!(name: n.downcase) }
    recipe.tags = desired
  end

  def prune_stale_meal_plan_items
    MealPlan.reconcile_kitchen!(kitchen)
  end
end
