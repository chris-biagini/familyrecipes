# frozen_string_literal: true

# Cascading Markdown updates when a recipe is renamed or deleted. On rename,
# rewrites "@[Old Title]" → "@[New Title]" in all referencing recipes' Markdown
# source and re-imports them. On delete, strips the "@[...]" syntax to leave
# plain text. Both operations return the list of affected recipe titles so the
# controller can report them.
class CrossReferenceUpdater
  def self.strip_references(recipe)
    new(recipe).strip_references
  end

  def self.rename_references(old_title:, new_title:, kitchen:)
    slug = FamilyRecipes.slugify(old_title)
    recipe = kitchen.recipes.find_by(slug: slug)
    return [] unless recipe

    new(recipe).rename_references(new_title)
  end

  def initialize(recipe)
    @recipe = recipe
  end

  def strip_references
    update_referencing_recipes { |source, title| source.gsub("@[#{title}]", title) }
  end

  def rename_references(new_title)
    old_title = @recipe.title
    update_referencing_recipes { |source, _| source.gsub("@[#{old_title}]", "@[#{new_title}]") }
  end

  private

  def update_referencing_recipes
    referencing = @recipe.referencing_recipes.includes(:category)
    return [] if referencing.empty?

    referencing.map do |ref_recipe|
      updated_source = yield(ref_recipe.markdown_source, @recipe.title)
      MarkdownImporter.import(updated_source, kitchen: ref_recipe.kitchen)
      ref_recipe.title
    end
  end
end
