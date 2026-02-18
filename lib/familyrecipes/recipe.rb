# Recipe class
#
# Parses and encapsulates an entire recipe

class Recipe
  attr_reader :title, :description, :yield_line, :steps, :footer, :source, :id, :version_hash, :category

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
    @yield_line = nil
    @steps = []
    @footer = nil

    parse_recipe
  end

  def relative_url
    @id
  end

  def to_html(erb_template_path:)
    template = File.read(erb_template_path)
    ERB.new(template, trim_mode: '-').result_with_hash(
      markdown: MARKDOWN,
      render: ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) },
      title: @title,
      description: @description,
      yield_line: @yield_line,
      steps: @steps,
      footer: @footer,
      id: @id,
      version_hash: @version_hash
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
    # Group all ingredients by normalized name, preserving first-seen order
    groups = {}
    @steps.flat_map(&:ingredients).each do |ingredient|
      name = ingredient.normalized_name(alias_map)
      (groups[name] ||= []) << ingredient
    end

    groups.map do |name, ingredients|
      [name, IngredientAggregator.aggregate_amounts(ingredients)]
    end
  end

  # Ingredients with quantities including expanded cross-references — used for grocery list
  def all_ingredients_with_quantities(alias_map, recipe_map)
    own = ingredients_with_quantities(alias_map)

    # Merge in cross-reference ingredients
    merged = {}
    own.each { |name, amounts| merged[name] = amounts }

    cross_references.each do |xref|
      xref.expanded_ingredients(recipe_map, alias_map).each do |name, amounts|
        if merged.key?(name)
          merged[name] = merge_amounts(merged[name], amounts)
        else
          merged[name] = amounts
        end
      end
    end

    merged.map { |name, amounts| [name, amounts] }
  end

  private

  def merge_amounts(existing, new_amounts)
    # Combine amount arrays, summing matching units
    sums = {}
    has_nil = false

    [existing, new_amounts].each do |amounts|
      amounts.each do |amount|
        if amount.nil?
          has_nil = true
        else
          value, unit = amount
          sums[unit] = (sums[unit] || 0.0) + value
        end
      end
    end

    result = sums.map { |unit, value| [value, unit] }
    result << nil if has_nil
    result
  end

  def parse_recipe
    # Use the new two-phase parser
    tokens = LineClassifier.classify(@source)
    builder = RecipeBuilder.new(tokens)
    doc = builder.build

    @title = doc[:title]
    @description = doc[:description]
    @yield_line = doc[:yield_line]
    @steps = build_steps(doc[:steps])
    @footer = doc[:footer]

    if @steps.empty?
      raise StandardError, "Invalid recipe format: Must have at least one step."
    end
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
