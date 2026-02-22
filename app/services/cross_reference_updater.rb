# frozen_string_literal: true

class CrossReferenceUpdater
  def self.strip_references(recipe)
    new(recipe).strip_references
  end

  def self.rename_references(old_title:, new_title:)
    slug = FamilyRecipes.slugify(old_title)
    recipe = Recipe.find_by(slug: slug)
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

  def update_referencing_recipes(&block)
    referencing = @recipe.referencing_recipes.includes(:category)
    return [] if referencing.empty?

    referencing.map do |ref_recipe|
      updated_source = block.call(ref_recipe.markdown_source, @recipe.title)
      MarkdownImporter.import(updated_source)
      ref_recipe.title
    end
  end
end
