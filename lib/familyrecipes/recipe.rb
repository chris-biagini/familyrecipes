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

  def all_ingredients(alias_map = {})
    @steps.flat_map(&:ingredients).uniq { |ingredient| ingredient.normalized_name(alias_map) }
  end

  def all_ingredient_names(alias_map = {})
    @steps
      .flat_map(&:ingredients)
      .map { |ingredient| ingredient.normalized_name(alias_map) }
      .uniq
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

  private

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
        ingredients: build_ingredients(data[:ingredients]),
        instructions: data[:instructions]
      )
    end
  end

  # Convert ingredient hashes from IngredientParser into Ingredient objects
  def build_ingredients(ingredient_data)
    ingredient_data.map do |data|
      Ingredient.new(
        name: data[:name],
        quantity: data[:quantity],
        prep_note: data[:prep_note]
      )
    end
  end
end
