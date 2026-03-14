# frozen_string_literal: true

# The sole write path for getting recipes into the database. Parses Markdown
# through the FamilyRecipes parser pipeline (LineClassifier → RecipeBuilder),
# then upserts the Recipe and its Steps, Ingredients, and CrossReferences in a
# transaction. Also processes instructions through ScalableNumberPreprocessor
# to generate the scalable-number HTML stored in Step#processed_instructions.
#
# Steps come in two flavors: content steps (ingredients + instructions) and
# cross-reference steps (> @[...] syntax, exactly one CrossReference, no ingredients
# or instructions). The step-level :cross_reference key drives this branching.
#
# Kitchen-scoped (requires kitchen: keyword) and idempotent — db:seed calls
# this repeatedly. Returns an ImportResult (recipe + front_matter_tags) so
# callers like RecipeWriteService can access parsed metadata without re-parsing.
# Category resolves via: explicit argument → front matter → Miscellaneous default.
# After import, resolves pending cross-references, computes nutrition synchronously
# (RecipeNutritionJob), and enqueues CascadeNutritionJob async so parent recipes
# update without blocking the saving user.
class MarkdownImporter
  class SlugCollisionError < RuntimeError; end

  ImportResult = Data.define(:recipe, :front_matter_tags)

  def self.import(markdown_source, kitchen:, category:)
    new(markdown_source, kitchen:, category:).run
  end

  def initialize(markdown_source, kitchen:, category:, parsed: nil)
    @markdown_source = markdown_source
    @kitchen = kitchen
    @category = category
    @parsed = parsed || parse_markdown
  end

  def run
    recipe = save_recipe
    CrossReference.resolve_pending(kitchen: kitchen)
    compute_nutrition(recipe)
    ImportResult.new(recipe:, front_matter_tags: parsed.dig(:front_matter, :tags))
  end

  private

  attr_reader :markdown_source, :kitchen, :category, :parsed

  def save_recipe
    ActiveRecord::Base.transaction do
      recipe = find_or_initialize_recipe
      update_recipe_attributes(recipe)
      recipe.save!
      replace_steps(recipe)
      recipe
    end
  end

  def compute_nutrition(recipe)
    RecipeNutritionJob.perform_now(recipe)
    CascadeNutritionJob.perform_later(recipe)
  end

  def parse_markdown
    tokens = LineClassifier.classify(markdown_source)
    RecipeBuilder.new(tokens).build
  end

  def find_or_initialize_recipe
    slug = FamilyRecipes.slugify(parsed[:title])
    recipe = kitchen.recipes.find_or_initialize_by(slug: slug)
    check_slug_collision!(recipe)
    recipe
  end

  def check_slug_collision!(recipe)
    return unless recipe.persisted?
    return if recipe.title == parsed[:title]

    raise SlugCollisionError,
          "A recipe with a similar name already exists: '#{recipe.title}'"
  end

  def update_recipe_attributes(recipe)
    makes_qty, makes_unit = FamilyRecipes::Recipe.parse_makes(parsed[:front_matter][:makes])

    recipe.assign_attributes(
      title: parsed[:title],
      description: parsed[:description],
      category: resolved_category,
      kitchen: kitchen,
      makes_quantity: makes_qty,
      makes_unit_noun: makes_unit,
      serves: parsed[:front_matter][:serves]&.to_i,
      footer: parsed[:footer],
      markdown_source: markdown_source
    )
  end

  def resolved_category
    category || resolve_front_matter_category || default_category
  end

  def resolve_front_matter_category
    name = parsed[:front_matter][:category]
    return unless name

    kitchen.categories.find_or_create_by!(name:)
  end

  def default_category
    slug = FamilyRecipes.slugify('Miscellaneous')
    kitchen.categories.find_or_create_by!(slug:) do |cat|
      cat.name = 'Miscellaneous'
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def replace_steps(recipe)
    recipe.steps.destroy_all

    parsed[:steps].each_with_index do |step_data, index|
      step = recipe.steps.create!(
        title: step_data[:tldr],
        instructions: step_data[:cross_reference] ? nil : step_data[:instructions],
        processed_instructions: step_data[:cross_reference] ? nil : process_instructions(step_data[:instructions]),
        position: index
      )

      if step_data[:cross_reference]
        import_cross_reference(step, step_data[:cross_reference])
      else
        import_step_items(step, step_data[:ingredients])
      end
    end
  end

  def process_instructions(text)
    return if text.blank?

    html = FamilyRecipes::Recipe::MARKDOWN.render(text)
    ScalableNumberPreprocessor.process_instructions(html)
  end

  def import_step_items(step, ingredient_data_list)
    ingredient_data_list.each_with_index do |data, index|
      import_ingredient(step, data, index)
    end
  end

  def import_ingredient(step, data, position)
    qty, unit = FamilyRecipes::Ingredient.split_quantity(data[:quantity])

    step.ingredients.create!(
      name: data[:name],
      quantity: qty,
      unit: unit,
      prep_note: data[:prep_note],
      position: position
    )
  end

  def import_cross_reference(step, data, position = 0)
    target_slug = FamilyRecipes.slugify(data[:target_title])
    target = kitchen.recipes.find_by(slug: target_slug)

    step.cross_references.create!(
      target_recipe: target,
      target_slug: target_slug,
      target_title: data[:target_title],
      multiplier: data[:multiplier] || 1.0,
      prep_note: data[:prep_note],
      position: position
    )
  end
end
