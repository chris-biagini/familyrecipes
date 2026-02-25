# frozen_string_literal: true

class MarkdownValidator
  def self.validate(markdown_source)
    new(markdown_source).validate
  end

  def initialize(markdown_source)
    @markdown_source = markdown_source
  end

  def validate
    return ['Recipe cannot be blank.'] if @markdown_source.blank?

    parsed = parse
    errors = []
    errors << 'Category is required in front matter (e.g., "Category: Bread").' unless parsed[:front_matter][:category]
    errors << 'Recipe must have at least one step (## Step Name).' if parsed[:steps].empty?
    errors
  rescue RuntimeError => error
    [error.message]
  end

  private

  def parse
    tokens = LineClassifier.classify(@markdown_source)
    RecipeBuilder.new(tokens).build
  end
end
