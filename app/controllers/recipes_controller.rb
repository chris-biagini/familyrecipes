# frozen_string_literal: true

# Thin HTTP adapter for recipe CRUD and raw exports. Show is public; writes
# require membership. Validates Markdown params, delegates to RecipeWriteService
# for orchestration, and renders JSON responses for writes. Also serves raw
# markdown (.md) and rendered HTML (.html) as easter-egg endpoints — no UI
# links to these. All domain logic (import, broadcast, cleanup) lives in the
# service.
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[content create update destroy]

  def show
    @recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
    @all_categories = current_kitchen.categories.ordered
  end

  def content
    recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
    render json: { markdown_source: recipe.markdown_source }
  end

  def show_markdown
    recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
    render plain: recipe.markdown_source, content_type: 'text/plain; charset=utf-8'
  end

  def show_html
    recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
    body = FamilyRecipes::Recipe::MARKDOWN.render(recipe.markdown_source)
    render html: minimal_html_document(title: recipe.title, body:), layout: false
  end

  def create
    return render_validation_errors if validation_errors.any?

    result = RecipeWriteService.create(
      markdown: params[:markdown_source], kitchen: current_kitchen,
      category_name: params[:category], tags: params[:tags]
    )
    render json: { redirect_url: recipe_path(result.recipe.slug) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update
    current_kitchen.recipes.find_by!(slug: params[:slug])
    return render_validation_errors if validation_errors.any?

    result = RecipeWriteService.update(
      slug: params[:slug], markdown: params[:markdown_source],
      kitchen: current_kitchen, category_name: params[:category],
      tags: params[:tags]
    )
    render json: update_response(result)
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
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

  def update_response(result)
    response = { slug: result.recipe.slug }
    response[:updated_references] = result.updated_references if result.updated_references.any?
    response
  end
end
