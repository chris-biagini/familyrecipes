# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), broadcast
# real-time updates (RecipeBroadcaster), clean up orphan categories, and prune
# stale meal plan entries. Controllers validate input and render responses;
# this service owns domain orchestration.
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

  private

  attr_reader :kitchen

  def import_and_timestamp(markdown)
    recipe = MarkdownImporter.import(markdown, kitchen:)
    recipe.update!(edited_at: Time.current)
    recipe
  end

  def post_write_cleanup
    Category.cleanup_orphans(kitchen)
    MealPlan.prune_stale_items(kitchen:)
  end
end
