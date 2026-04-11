# frozen_string_literal: true

# Quick-check validator for user-submitted recipe Markdown. Runs the parser
# pipeline without touching the database to surface structural errors (missing
# title, no steps) before MarkdownImporter is called. Used by
# RecipesController on create and update.
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
    errors << 'Recipe must have at least one step (## Step Name).' if parsed[:steps].empty?
    errors
  rescue Mirepoix::ParseError => error
    [error.message]
  end

  private

  def parse
    tokens = LineClassifier.classify(@markdown_source)
    RecipeBuilder.new(tokens).build
  end
end
