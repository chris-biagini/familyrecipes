# frozen_string_literal: true

# Thin HTTP adapter for recipe CRUD and raw exports. Show is public; writes
# require membership. Validates Markdown params, delegates to RecipeWriteService
# for orchestration, and renders JSON responses for writes. Also serves raw
# markdown (.md) and rendered HTML (.html) as easter-egg endpoints — no UI
# links to these. All domain logic (import, broadcast, cleanup) lives in the
# service.
class RecipesController < ApplicationController
  include StructureValidation

  before_action :require_membership, only: %i[content editor_frame create update destroy parse serialize]
  before_action :prevent_html_caching, only: :show

  def show
    @recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
    @all_categories = current_kitchen.categories.ordered
  end

  def content
    recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
    markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

    render json: {
      markdown_source: markdown,
      category: recipe.category&.name,
      tags: recipe.tags.pluck(:name),
      structure: ir
    }
  end

  def editor_frame
    recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
    markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

    render partial: 'recipes/editor_frame', locals: {
      recipe: recipe,
      markdown_source: markdown,
      structure: ir
    }, layout: false
  end

  def parse
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    tokens = LineClassifier.classify(params[:markdown_source])
    ir = RecipeBuilder.new(tokens).build
    render json: ir
  end

  def serialize
    markdown_source = FamilyRecipes::RecipeSerializer.serialize(structure_params)
    render json: { markdown_source: }
  end

  def show_markdown
    recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    render plain: generate_markdown(recipe), content_type: 'text/plain; charset=utf-8'
  end

  def show_html
    recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    body = FamilyRecipes::Recipe::MARKDOWN.render(generate_markdown(recipe))
    render html: minimal_html_document(title: recipe.title, body:), layout: false
  end

  def create
    result = create_result
    render json: { redirect_url: recipe_path(result.recipe.slug) } unless performed?
  rescue ActiveRecord::RecordInvalid, FamilyRecipes::ParseError, MarkdownImporter::SlugCollisionError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update
    current_kitchen.recipes.find_by!(slug: params[:slug])
    result = update_result
    render json: update_response(result) unless performed?
  rescue ActiveRecord::RecordInvalid, FamilyRecipes::ParseError, MarkdownImporter::SlugCollisionError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def destroy
    RecipeWriteService.destroy(slug: params[:slug], kitchen: current_kitchen)
    render json: { redirect_url: home_path }
  end

  private

  def validation_errors
    @validation_errors ||= MarkdownValidator.validate(params[:markdown_source])
  end

  def render_validation_errors
    render json: { errors: @validation_errors }, status: :unprocessable_content
  end

  def generate_markdown(recipe)
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
    FamilyRecipes::RecipeSerializer.serialize(ir)
  end

  def minimal_html_document(title:, body:)
    <<~HTML.html_safe # rubocop:disable Rails/OutputSafety
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>#{ERB::Util.html_escape(title)}</title>
      </head>
      <body>
      #{body}
      </body>
      </html>
    HTML
  end

  def create_result
    if params[:structure]
      return RecipeWriteService.create_from_structure(
        structure: structure_params, kitchen: current_kitchen
      )
    end

    render_validation_errors and return if validation_errors.any?

    RecipeWriteService.create(
      markdown: params[:markdown_source], kitchen: current_kitchen,
      category_name: params[:category], tags: params[:tags]
    )
  end

  def update_result
    if params[:structure]
      return RecipeWriteService.update_from_structure(
        slug: params[:slug], structure: structure_params, kitchen: current_kitchen
      )
    end

    render_validation_errors and return if validation_errors.any?

    RecipeWriteService.update(
      slug: params[:slug], markdown: params[:markdown_source],
      kitchen: current_kitchen, category_name: params[:category], tags: params[:tags]
    )
  end

  def structure_params
    validated_recipe_structure
  end

  def update_response(result)
    response = { slug: result.recipe.slug }
    response[:updated_references] = result.updated_references if result.updated_references.any?
    response
  end
end
