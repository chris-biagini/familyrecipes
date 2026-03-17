# frozen_string_literal: true

# Cascading Markdown updates when a recipe is renamed. Generates markdown
# from AR records via RecipeSerializer, rewrites "@[Old Title]" →
# "@[New Title]", and re-imports. Returns affected recipe titles.
# Recipe deletion relies on dependent: :nullify on
# inbound_cross_references — no Markdown rewriting needed.
class CrossReferenceUpdater
  def self.rename_references(old_title:, new_title:, kitchen:)
    slug = FamilyRecipes.slugify(old_title)
    recipe = kitchen.recipes.find_by(slug: slug)
    return [] unless recipe

    new(recipe).rename_references(new_title)
  end

  def initialize(recipe)
    @recipe = recipe
  end

  def rename_references(new_title)
    normalized_old = FamilyRecipes.normalize_for_comparison(@recipe.title)
    update_referencing_recipes do |source, _|
      source.gsub(/@\[([^\]]+)\]/) do |match|
        ref_title = Regexp.last_match(1)
        FamilyRecipes.normalize_for_comparison(ref_title) == normalized_old ? "@[#{new_title}]" : match
      end
    end
  end

  private

  def update_referencing_recipes
    referencing = @recipe.referencing_recipes
                         .includes(:category, :tags, steps: %i[ingredients cross_references])
    return [] if referencing.empty?

    referencing.map do |ref_recipe|
      markdown = generate_markdown(ref_recipe)
      updated_markdown = yield(markdown, @recipe.title)
      MarkdownImporter.import(updated_markdown, kitchen: ref_recipe.kitchen, category: ref_recipe.category)
      ref_recipe.title
    end
  end

  def generate_markdown(recipe)
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
    FamilyRecipes::RecipeSerializer.serialize(ir)
  end
end
