# frozen_string_literal: true

class RecipesController < ApplicationController
  def show
    @recipe = Recipe.includes(steps: :ingredients).find_by!(slug: params[:slug])
    @parsed_recipe = parse_recipe
    @nutrition = calculate_nutrition
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source])
    recipe.update!(edited_at: Time.current)

    render json: { redirect_url: recipe_path(recipe.slug) }
  end

  def update
    @recipe = Recipe.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source])

    updated_references = if title_changed?(old_title, recipe.title)
                           CrossReferenceUpdater.rename_references(old_title: old_title, new_title: recipe.title)
                         else
                           []
                         end

    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    @recipe = Recipe.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    @recipe.destroy!
    Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: root_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def title_changed?(old_title, new_title)
    old_title != new_title
  end

  def parse_recipe
    FamilyRecipes::Recipe.new(
      markdown_source: @recipe.markdown_source,
      id: @recipe.slug,
      category: @recipe.category.name
    )
  end

  def calculate_nutrition
    nutrition_data = load_nutrition_data
    return unless nutrition_data

    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
    calculator.calculate(@parsed_recipe, alias_map, recipe_map)
  end

  def load_nutrition_data
    path = Rails.root.join('resources/nutrition-data.yaml')
    return unless File.exist?(path)

    YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def grocery_aisles
    @grocery_aisles ||= load_grocery_aisles
  end

  def load_grocery_aisles
    doc = SiteDocument.find_by(name: 'grocery_aisles')
    return FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml')) unless doc

    FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
  end

  def alias_map
    @alias_map ||= FamilyRecipes.build_alias_map(grocery_aisles)
  end

  def omit_set
    @omit_set ||= build_omit_set
  end

  def build_omit_set
    omit_key = grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    grocery_aisles[omit_key].to_set { |item| item[:name].downcase }
  end

  def recipe_map
    @recipe_map ||= Recipe.includes(:category).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end
end
