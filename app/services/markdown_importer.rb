# frozen_string_literal: true

# The sole write path for getting recipes into the database. Parses Markdown
# through the FamilyRecipes parser pipeline (LineClassifier → RecipeBuilder),
# then upserts the Recipe and its Steps, Ingredients, and CrossReferences in a
# transaction. Also processes instructions through ScalableNumberPreprocessor
# to generate the scalable-number HTML stored in Step#processed_instructions.
#
# Kitchen-scoped (requires kitchen: keyword) and idempotent — db:seed calls
# this repeatedly. After import, resolves pending cross-references and triggers
# nutrition calculation via RecipeNutritionJob and CascadeNutritionJob.
class MarkdownImporter
  def self.import(markdown_source, kitchen:)
    new(markdown_source, kitchen: kitchen).import
  end

  def initialize(markdown_source, kitchen:)
    @markdown_source = markdown_source
    @kitchen = kitchen
    @parsed = parse_markdown
  end

  def import
    recipe = save_recipe
    CrossReference.resolve_pending(kitchen: kitchen)
    compute_nutrition(recipe)
    recipe
  end

  private

  attr_reader :markdown_source, :kitchen, :parsed

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
    CascadeNutritionJob.perform_now(recipe)
  end

  def parse_markdown
    tokens = LineClassifier.classify(markdown_source)
    RecipeBuilder.new(tokens).build
  end

  def find_or_initialize_recipe
    slug = FamilyRecipes.slugify(parsed[:title])
    kitchen.recipes.find_or_initialize_by(slug: slug)
  end

  def update_recipe_attributes(recipe)
    category = find_or_create_category(parsed[:front_matter][:category])
    makes_qty, makes_unit = parse_makes(parsed[:front_matter][:makes])

    recipe.assign_attributes(
      title: parsed[:title],
      description: parsed[:description],
      category: category,
      kitchen: kitchen,
      makes_quantity: makes_qty,
      makes_unit_noun: makes_unit,
      serves: parsed[:front_matter][:serves]&.to_i,
      footer: parsed[:footer],
      markdown_source: markdown_source
    )
  end

  def find_or_create_category(name)
    slug = FamilyRecipes.slugify(name)
    kitchen.categories.find_or_create_by!(slug: slug) do |cat|
      cat.name = name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def parse_makes(makes_string)
    return [nil, nil] unless makes_string

    match = makes_string.match(/\A(\S+)\s+(.+)/)
    return [nil, nil] unless match

    [match[1].to_f, match[2]]
  end

  def replace_steps(recipe)
    recipe.steps.destroy_all

    parsed[:steps].each_with_index do |step_data, index|
      step = recipe.steps.create!(
        title: step_data[:tldr],
        instructions: step_data[:instructions],
        processed_instructions: process_instructions(step_data[:instructions]),
        position: index
      )

      import_step_items(step, step_data[:ingredients])
    end
  end

  def process_instructions(text)
    return if text.blank?

    # Render markdown first (escapes user HTML), then insert scalable spans
    html = FamilyRecipes::Recipe::MARKDOWN.render(text)
    ScalableNumberPreprocessor.process_instructions(html)
  end

  def import_step_items(step, ingredient_data_list)
    ingredient_data_list.each_with_index do |data, index|
      if data[:cross_reference]
        import_cross_reference(step, data, index)
      else
        import_ingredient(step, data, index)
      end
    end
  end

  def import_ingredient(step, data, position)
    qty, unit = split_quantity(data[:quantity])

    step.ingredients.create!(
      name: data[:name],
      quantity: qty,
      unit: unit,
      prep_note: data[:prep_note],
      position: position
    )
  end

  def import_cross_reference(step, data, position)
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

  def split_quantity(quantity_string)
    return [nil, nil] if quantity_string.nil? || quantity_string.strip.empty?

    parts = quantity_string.strip.split(' ', 2)
    [parts[0], parts[1]]
  end
end
