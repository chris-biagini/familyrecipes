# frozen_string_literal: true

module FamilyRecipes
  class Recipe
    attr_reader :title, :description, :makes, :serves, :steps, :footer, :source, :id, :version_hash, :category

    MARKDOWN = Redcarpet::Markdown.new(
      Redcarpet::Render::SmartyHTML.new(escape_html: true),
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

    def cross_references
      @steps.flat_map(&:cross_references)
    end

    def all_ingredients
      @steps.flat_map(&:ingredients).uniq(&:name)
    end

    def all_ingredient_names
      @steps.flat_map(&:ingredients).map(&:name).uniq
    end

    def own_ingredients_with_quantities
      ingredients_with_quantities
    end

    def ingredients_with_quantities
      @steps.flat_map(&:ingredients)
            .group_by(&:name)
            .map { |name, ingredients| [name, IngredientAggregator.aggregate_amounts(ingredients)] }
    end

    def all_ingredients_with_quantities(recipe_map)
      cross_references.each_with_object(ingredients_with_quantities.to_h) do |xref, merged|
        xref.expanded_ingredients(recipe_map).each do |name, amounts|
          merged[name] = merged.key?(name) ? IngredientAggregator.merge_amounts(merged[name], amounts) : amounts
        end
      end.to_a
    end

    private

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

    def build_steps(step_data)
      step_data.map do |data|
        Step.new(
          tldr: data[:tldr],
          ingredient_list_items: build_ingredient_items(data[:ingredients]),
          instructions: data[:instructions]
        )
      end
    end

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
end
