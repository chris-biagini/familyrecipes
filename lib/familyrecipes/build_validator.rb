# frozen_string_literal: true

module FamilyRecipes
  class BuildValidator
    def initialize(recipes:, quick_bites:, recipe_map:, nutrition_calculator: nil)
      @recipes = recipes
      @quick_bites = quick_bites
      @recipe_map = recipe_map
      @nutrition_calculator = nutrition_calculator
    end

    def validate_cross_references
      print 'Validating cross-references...'

      @recipes.each do |recipe|
        validate_title_slug(recipe)
        validate_references_resolve(recipe)
        detect_cycles(recipe, [])
      end

      print "done!\n"
    end

    def validate_ingredients
      print 'Validating ingredients...'

      ingredients_to_recipes = build_ingredient_recipe_index
      known = IngredientCatalog.pluck(:ingredient_name).to_set(&:downcase)

      unknown_ingredients = ingredients_to_recipes.keys.reject do |name|
        known.include?(name.downcase)
      end.to_set

      if unknown_ingredients.any?
        print_unknown_ingredients(unknown_ingredients, ingredients_to_recipes)
      else
        print "done! (All ingredients validated.)\n"
      end
    end

    def validate_nutrition
      return unless @nutrition_calculator

      print 'Validating nutrition data...'

      omit_set = IngredientCatalog.where(aisle: 'omit').pluck(:ingredient_name).to_set(&:downcase)
      ingredients_to_recipes = build_nutrition_recipe_index(omit_set)
      missing = find_missing_nutrition(ingredients_to_recipes)
      unresolvable, unquantified = find_nutrition_issues(omit_set)

      print_nutrition_warnings(missing, unresolvable, unquantified, ingredients_to_recipes)
    end

    private

    def validate_title_slug(recipe)
      title_slug = FamilyRecipes.slugify(recipe.title)
      return if title_slug == recipe.id

      raise StandardError,
            "Title/filename mismatch: \"#{recipe.title}\" (slug: #{title_slug}) vs filename slug: #{recipe.id}"
    end

    def validate_references_resolve(recipe)
      recipe.cross_references.each do |xref|
        next if @recipe_map.key?(xref.target_slug)

        raise StandardError,
              "Unresolved cross-reference in \"#{recipe.title}\": " \
              "@[#{xref.target_title}] (slug: #{xref.target_slug})"
      end
    end

    def detect_cycles(recipe, visited)
      if visited.include?(recipe.id)
        cycle = visited[visited.index(recipe.id)..] + [recipe.id]
        raise StandardError, "Circular cross-reference detected: #{cycle.join(' -> ')}"
      end

      recipe.cross_references.each do |xref|
        target = @recipe_map[xref.target_slug]
        next unless target

        detect_cycles(target, visited + [recipe.id])
      end
    end

    def build_ingredient_recipe_index
      Hash.new { |h, k| h[k] = [] }.tap do |index|
        @recipes.each { |r| r.all_ingredients.each { |i| index[i.name] << r.title } }
        @quick_bites.each { |qb| qb.ingredients.each { |name| index[name] << qb.title } }
      end
    end

    def print_unknown_ingredients(unknown_ingredients, ingredients_to_recipes)
      puts "\n"
      puts 'WARNING: The following ingredients are not in any IngredientCatalog:'
      unknown_ingredients.sort.each do |ing|
        recipes = ingredients_to_recipes[ing].uniq.sort
        puts "  - #{ing} (in: #{recipes.join(', ')})"
      end
      puts 'Add them via bin/nutrition or the web editor.'
      puts ''
    end

    def build_nutrition_recipe_index(omit_set)
      @recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
        recipe.all_ingredient_names.each do |name|
          index[name] << recipe.title unless omit_set.include?(name.downcase)
        end
      end
    end

    def find_missing_nutrition(ingredients_to_recipes)
      ingredients_to_recipes.keys.reject { |name| @nutrition_calculator.nutrition_data.key?(name) }
    end

    def find_nutrition_issues(omit_set)
      unresolvable = Hash.new { |h, k| h[k] = { units: Set.new, recipes: [] } }
      unquantified = Hash.new { |h, k| h[k] = [] }

      @recipes.each do |recipe|
        check_recipe_nutrition(recipe, unresolvable, unquantified, omit_set)
      end

      [unresolvable, unquantified]
    end

    def check_recipe_nutrition(recipe, unresolvable, unquantified, omit_set)
      recipe.all_ingredients_with_quantities(@recipe_map).each do |name, amounts|
        next if omit_set.include?(name.downcase)

        entry = @nutrition_calculator.nutrition_data[name]
        next unless entry

        non_nil_amounts = amounts.compact
        unquantified[name] |= [recipe.title] if non_nil_amounts.empty?
        check_amounts_resolvable(name, non_nil_amounts, entry, unresolvable, recipe)
      end
    end

    def check_amounts_resolvable(name, amounts, entry, unresolvable, recipe)
      amounts.each do |quantity|
        next if quantity.value.nil?
        next if @nutrition_calculator.resolvable?(quantity.value, quantity.unit, entry)

        info = unresolvable[name]
        info[:units] << (quantity.unit || '(bare count)')
        info[:recipes] |= [recipe.title]
      end
    end

    def print_nutrition_warnings(missing, unresolvable, unquantified, ingredients_to_recipes)
      has_warnings = missing.any? || unresolvable.any? || unquantified.any?

      print_missing_nutrition(missing, ingredients_to_recipes) if missing.any?
      print_unresolvable_units(unresolvable, first: missing.none?) if unresolvable.any?
      print_unquantified_ingredients(unquantified, first: missing.none? && unresolvable.none?) if unquantified.any?

      if has_warnings
        puts ''
        puts 'Use bin/nutrition to add data, or edit db/seeds/resources/ingredient-catalog.yaml directly.'
        puts ''
      else
        print "done! (All ingredients have nutrition data.)\n"
      end
    end

    def print_missing_nutrition(missing, ingredients_to_recipes)
      puts "\n"
      puts 'WARNING: Missing nutrition data:'
      missing.sort.each do |name|
        recipes = ingredients_to_recipes[name].uniq.sort
        puts "  - #{name} (in: #{recipes.join(', ')})"
      end
    end

    def print_unresolvable_units(unresolvable, first: true)
      puts "\n" if first
      puts 'WARNING: Missing unit conversions:'
      unresolvable.sort_by { |name, _| name }.each do |name, info|
        recipes = info[:recipes].sort
        units = info[:units].to_a.sort.join(', ')
        puts "  - #{name}: '#{units}' (in: #{recipes.join(', ')})"
      end
    end

    def print_unquantified_ingredients(unquantified, first: true)
      puts "\n" if first
      puts 'NOTE: Unquantified ingredients (not counted in nutrition):'
      unquantified.sort_by { |name, _| name }.each do |name, recipes|
        puts "  - #{name} (in: #{recipes.sort.join(', ')})"
      end
    end
  end
end
