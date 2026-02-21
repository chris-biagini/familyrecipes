# frozen_string_literal: true

class RecipeRenderer
  class << self
    def render_html(recipe)
      nutrition = nutrition_calculator&.calculate(recipe, alias_map, recipe_map)
      recipe.to_html(erb_template_path: template_path, nutrition: nutrition)
    end

    def reset_cache!
      @grocery_aisles = nil
      @alias_map = nil
      @omit_set = nil
      @nutrition_calculator = nil
      @recipe_map = nil
    end

    private

    def template_path
      Rails.root.join('templates/web/recipe-template.html.erb').to_s
    end

    def grocery_aisles
      @grocery_aisles ||= FamilyRecipes.parse_grocery_info(grocery_info_path)
    end

    def alias_map
      @alias_map ||= FamilyRecipes.build_alias_map(grocery_aisles)
    end

    def omit_set
      @omit_set ||= build_omit_set
    end

    def build_omit_set
      (grocery_aisles['Omit_From_List'] || [])
        .flat_map { |item| [item[:name], *item[:aliases]].map(&:downcase) }
        .to_set
    end

    def nutrition_calculator
      @nutrition_calculator ||= load_nutrition_calculator
    end

    def recipe_map
      @recipe_map ||= FamilyRecipes.parse_recipes(recipes_dir).to_h { |r| [r.id, r] }
    end

    def load_nutrition_calculator
      return unless File.exist?(nutrition_data_path)

      data = YAML.safe_load_file(nutrition_data_path, permitted_classes: [], permitted_symbols: [],
                                                      aliases: false) || {}
      FamilyRecipes::NutritionCalculator.new(data, omit_set: omit_set)
    end

    def grocery_info_path = Rails.root.join('resources/grocery-info.yaml').to_s

    def nutrition_data_path = Rails.root.join('resources/nutrition-data.yaml').to_s

    def recipes_dir = Rails.root.join('recipes').to_s
  end
end
