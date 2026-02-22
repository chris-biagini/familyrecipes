# frozen_string_literal: true

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
    ActiveRecord::Base.transaction do
      recipe = find_or_initialize_recipe
      update_recipe_attributes(recipe)
      recipe.save!
      replace_steps(recipe)
      rebuild_dependencies(recipe)
      recipe
    end
  end

  private

  attr_reader :markdown_source, :kitchen, :parsed

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
        position: index
      )

      import_ingredients(step, step_data[:ingredients])
    end
  end

  def import_ingredients(step, ingredient_data_list)
    ingredient_data_list.each_with_index do |data, index|
      next if data[:cross_reference]

      qty, unit = split_quantity(data[:quantity])

      step.ingredients.create!(
        name: data[:name],
        quantity: qty,
        unit: unit,
        prep_note: data[:prep_note],
        position: index
      )
    end
  end

  def split_quantity(quantity_string)
    return [nil, nil] if quantity_string.nil? || quantity_string.strip.empty?

    parts = quantity_string.strip.split(' ', 2)
    [parts[0], parts[1]]
  end

  def rebuild_dependencies(recipe)
    recipe.outbound_dependencies.destroy_all

    cross_refs = parsed[:steps].flat_map { |s| s[:ingredients].select { |i| i[:cross_reference] } }
    target_slugs = cross_refs.map { |ref| FamilyRecipes.slugify(ref[:target_title]) }.uniq

    target_slugs.each do |slug|
      target = Recipe.find_by(slug: slug)
      next unless target

      recipe.outbound_dependencies.create!(target_recipe: target)
    end
  end
end
