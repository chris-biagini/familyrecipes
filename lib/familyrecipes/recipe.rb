# Recipe class
#
# Parses and encapsulates an entire recipe

class Recipe
  attr_reader :title, :description, :yield_line, :steps, :footer, :source, :id, :version_hash, :category

  # Shared markdown renderer with SmartyPants for typographic quotes/dashes
  MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::SmartyHTML.new,
    tables: true,
    fenced_code_blocks: true,
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

  def all_ingredients
    # magic ruby syntax, returns a flat array of all unique ingredients
    @steps.flat_map(&:ingredients).uniq { |ingredient| ingredient.normalized_name }
  end

  def all_ingredient_names
    @steps
      .flat_map(&:ingredients)
      .map(&:normalized_name)
      .uniq
  end

  def ingredients_with_quantities
    # Group all ingredients by normalized name, preserving first-seen order
    groups = {}
    @steps.flat_map(&:ingredients).each do |ingredient|
      name = ingredient.normalized_name
      (groups[name] ||= []) << ingredient
    end

    groups.map do |name, ingredients|
      [name, aggregate_amounts(ingredients)]
    end
  end

  private

  def aggregate_amounts(ingredients)
    sums = {}        # unit -> numeric sum
    has_unquantified = false

    ingredients.each do |ingredient|
      raw_value = ingredient.quantity_value
      unit = ingredient.quantity_unit
      unit = Ingredient::UNIT_NORMALIZATIONS[unit] || unit if unit

      numeric = begin
        Float(raw_value)
      rescue StandardError
        nil
      end if raw_value

      if numeric
        sums[unit] = (sums[unit] || 0.0) + numeric
      else
        has_unquantified = true
      end
    end

    result = sums.map { |unit, value| [value, unit] }
    result << nil if has_unquantified
    result = [nil] if result.empty?
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
