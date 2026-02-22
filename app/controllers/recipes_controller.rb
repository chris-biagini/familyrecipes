# frozen_string_literal: true

class RecipesController < ApplicationController
  def show
    @recipe = Recipe.includes(steps: :ingredients).find_by!(slug: params[:slug])
    @parsed_recipe = parse_recipe
    @nutrition = calculate_nutrition
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def update
    @recipe = Recipe.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source])
    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    render json: { redirect_url: recipe_path(recipe.slug) }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

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
    @grocery_aisles ||= FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
  end

  def alias_map
    @alias_map ||= FamilyRecipes.build_alias_map(grocery_aisles)
  end

  def omit_set
    @omit_set ||= (grocery_aisles['Omit_From_List'] || []).flat_map do |item|
      [item[:name], *item[:aliases]].map(&:downcase)
    end.to_set
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
