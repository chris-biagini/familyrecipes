# frozen_string_literal: true

# Recipe class
#
# Parses and encapsulates an entire recipe

class Recipe
  attr_reader :title, :description, :makes, :serves, :steps, :footer, :source, :id, :version_hash, :category

  # Shared markdown renderer with SmartyPants for typographic quotes/dashes
  MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::SmartyHTML.new,
    autolink: true,
    no_intra_emphasis: true
  )

  def initialize(markdown_source:, id:, category:)
    @source = markdown_source
    @id = id
    @category = category

    @version_hash = Digest::SHA256.hexdigest(@source)

    @title = nil
    @description = nil
    @makes = nil
    @serves = nil
    @steps = []
    @footer = nil

    parse_recipe
  end

  def relative_url
    @id
  end

  def makes_quantity
    return unless @makes

    @makes.match(/\A(\S+)/)&.captures&.first
  end

  def makes_unit_noun
    return unless @makes

    @makes.match(/\A\S+\s+(.+)/)&.captures&.first
  end

  def to_html(erb_template_path:, nutrition: nil)
    template = File.read(erb_template_path)
    ERB.new(template, trim_mode: '-').result_with_hash(
      markdown: MARKDOWN,
      render: ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) },
      inflector: FamilyRecipes::Inflector,
      title: @title,
      description: @description,
      category: @category,
      makes: @makes,
      serves: @serves,
      steps: @steps,
      footer: @footer,
      id: @id,
      version_hash: @version_hash,
      nutrition: nutrition
    )
  end

  # All cross-references across all steps
  def cross_references
    @steps.flat_map(&:cross_references)
  end

  # Own ingredients only (excludes sub-recipe ingredients) — used for ingredient index
  def all_ingredients(alias_map = {})
    @steps.flat_map(&:ingredients).uniq { |ingredient| ingredient.normalized_name(alias_map) }
  end

  def all_ingredient_names(alias_map = {})
    @steps
      .flat_map(&:ingredients)
      .map { |ingredient| ingredient.normalized_name(alias_map) }
      .uniq
  end

  # Own ingredients with aggregated quantities (excludes sub-recipe ingredients)
  def own_ingredients_with_quantities(alias_map = {})
    ingredients_with_quantities(alias_map)
  end

  def ingredients_with_quantities(alias_map = {})
    @steps.flat_map(&:ingredients)
          .group_by { |i| i.normalized_name(alias_map) }
          .map { |name, ingredients| [name, IngredientAggregator.aggregate_amounts(ingredients)] }
  end

  # Ingredients with quantities including expanded cross-references — used for grocery list
  def all_ingredients_with_quantities(alias_map, recipe_map)
    cross_references.each_with_object(ingredients_with_quantities(alias_map).to_h) do |xref, merged|
      xref.expanded_ingredients(recipe_map, alias_map).each do |name, amounts|
        merged[name] = merged.key?(name) ? merge_amounts(merged[name], amounts) : amounts
      end
    end.to_a
  end

  private

  def merge_amounts(existing, new_amounts)
    all = existing + new_amounts
    has_nil = all.include?(nil)
    sums = all.compact.each_with_object(Hash.new(0.0)) do |quantity, h|
      h[quantity.unit] += quantity.value
    end

    result = sums.map { |unit, value| Quantity[value, unit] }
    result << nil if has_nil
    result
  end

  def parse_recipe
    tokens = LineClassifier.classify(@source)
    builder = RecipeBuilder.new(tokens)
    doc = builder.build

    @title = doc[:title]
    @description = doc[:description]
    @steps = build_steps(doc[:steps])
    @footer = doc[:footer]

    apply_front_matter(doc[:front_matter])
    validate_front_matter

    raise StandardError, 'Invalid recipe format: Must have at least one step.' if @steps.empty?
  end

  def apply_front_matter(fields)
    @makes = fields[:makes]
    @serves = fields[:serves]
    @front_matter_category = fields[:category]
  end

  def validate_front_matter
    raise "Missing 'Category:' in front matter for '#{@title}'." unless @front_matter_category

    validate_category_match
    validate_makes_has_unit_noun
  end

  def validate_category_match
    return if @front_matter_category == @category

    raise "Category mismatch for '#{@title}': " \
          "front matter says '#{@front_matter_category}' but file is in '#{@category}/' directory."
  end

  def validate_makes_has_unit_noun
    return unless @makes && !makes_unit_noun

    raise "Makes field for '#{@title}' requires a unit noun " \
          "(e.g., 'Makes: 12 pancakes', not 'Makes: 12')."
  end

  # Convert step hashes from RecipeBuilder into Step objects
  def build_steps(step_data)
    step_data.map do |data|
      Step.new(
        tldr: data[:tldr],
        ingredient_list_items: build_ingredient_items(data[:ingredients]),
        instructions: data[:instructions]
      )
    end
  end

  # Convert ingredient hashes from IngredientParser into Ingredient or CrossReference objects
  def build_ingredient_items(ingredient_data)
    ingredient_data.map do |data|
      if data[:cross_reference]
        CrossReference.new(
          target_title: data[:target_title],
          multiplier: data[:multiplier],
          prep_note: data[:prep_note]
        )
      else
        Ingredient.new(
          name: data[:name],
          quantity: data[:quantity],
          prep_note: data[:prep_note]
        )
      end
    end
  end
end
