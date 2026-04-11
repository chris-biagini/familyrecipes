# frozen_string_literal: true

# The sole write path for getting recipes into the database. Two entry points:
# `import` parses Markdown via the parser pipeline, `import_from_structure`
# accepts a pre-parsed IR hash directly. Both converge on `run`, which upserts
# the Recipe and its child records, resolves pending cross-references, and
# computes nutrition. AR records are the sole source of truth — no markdown
# is stored.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline (import path)
# - RecipeWriteService — primary caller for web operations
# - RecipeNutritionJob, CascadeNutritionJob — post-import nutrition
class MarkdownImporter
  class SlugCollisionError < RuntimeError; end

  ImportResult = Data.define(:recipe, :front_matter_tags)

  def self.import(markdown_source, kitchen:, category:)
    new(markdown_source, kitchen:, category:).run
  end

  def self.import_from_structure(ir_hash, kitchen:, category:)
    new(kitchen:, category:, parsed: ir_hash).run
  end

  def initialize(markdown_source = nil, kitchen:, category:, parsed: nil)
    @kitchen = kitchen
    @category = category
    @parsed = parsed || parse_markdown(markdown_source)
  end

  def run
    recipe = save_recipe
    CrossReference.resolve_pending(kitchen: kitchen)
    RecipeNutritionJob.perform_now(recipe)
    CascadeNutritionJob.perform_later(recipe)
    ImportResult.new(recipe:, front_matter_tags: parsed.dig(:front_matter, :tags))
  end

  private

  attr_reader :kitchen, :category, :parsed

  def save_recipe
    ActiveRecord::Base.transaction do
      recipe = find_or_initialize_recipe
      update_recipe_attributes(recipe)
      recipe.save!
      replace_steps(recipe)
      recipe
    end
  end

  def parse_markdown(markdown_source)
    raise ArgumentError, 'markdown_source required when parsed IR not provided' unless markdown_source

    RecipeBuilder.new(LineClassifier.classify(markdown_source)).build
  end

  def find_or_initialize_recipe
    slug = Mirepoix.slugify(parsed[:title])
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
    makes_qty, makes_unit = Mirepoix::Recipe.parse_makes(parsed[:front_matter][:makes])

    recipe.assign_attributes(
      title: parsed[:title],
      description: parsed[:description],
      category: resolved_category,
      kitchen: kitchen,
      makes_quantity: makes_qty,
      makes_unit_noun: makes_unit,
      serves: parsed[:front_matter][:serves]&.to_i,
      footer: parsed[:footer]
    )
  end

  def resolved_category
    category || resolve_front_matter_category || default_category
  end

  def resolve_front_matter_category
    name = parsed[:front_matter][:category]
    return unless name

    Category.find_or_create_for(kitchen, name)
  end

  def default_category
    Category.miscellaneous(kitchen)
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

    html = Mirepoix::Recipe::MARKDOWN.render(text)
    ScalableNumberPreprocessor.process_instructions(html)
  end

  def import_step_items(step, ingredient_data_list)
    ingredient_data_list.each_with_index do |data, index|
      import_ingredient(step, data, index)
    end
  end

  def import_ingredient(step, data, position)
    normalized = Mirepoix::Ingredient.normalize_quantity(data[:quantity])
    qty, unit = Mirepoix::Ingredient.split_quantity(normalized)
    low, high = Mirepoix::Ingredient.parse_range(qty)

    step.ingredients.create!(
      name: data[:name],
      quantity: qty,
      quantity_low: low,
      quantity_high: high,
      unit: unit,
      prep_note: data[:prep_note],
      position: position
    )
  end

  def import_cross_reference(step, data, position = 0)
    target_slug = Mirepoix.slugify(data[:target_title])
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
