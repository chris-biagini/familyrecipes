module FamilyRecipes
  class SiteGenerator
    def initialize(project_root, recipes: nil, quick_bites: nil)
      @project_root     = project_root
      @recipes_dir      = File.join(project_root, "recipes")
      @template_dir     = File.join(project_root, "templates/web")
      @resources_dir    = File.join(project_root, "resources/web")
      @output_dir       = File.join(project_root, "output/web")
      @grocery_info_path = File.join(project_root, "resources/grocery-info.yaml")
      @recipes     = recipes
      @quick_bites = quick_bites

      FamilyRecipes.template_dir = @template_dir
    end

    def generate
      load_grocery_info
      load_nutrition_data
      parse_recipes
      parse_quick_bites
      build_recipe_map
      validate_cross_references
      generate_recipe_pages
      copy_resources
      generate_homepage
      generate_index
      validate_ingredients
      validate_nutrition
      generate_groceries_page
    end

    private

    attr_reader :project_root, :recipes_dir, :template_dir, :resources_dir,
                :output_dir, :grocery_info_path

    def render
      @render ||= ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) }
    end

    def load_grocery_info
      print "Loading grocery info from #{grocery_info_path}..."
      @grocery_aisles = FamilyRecipes.parse_grocery_info(grocery_info_path)
      @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
      @known_ingredients = FamilyRecipes.build_known_ingredients(@grocery_aisles, @alias_map)
      @omit_set = (@grocery_aisles["Omit_From_List"] || []).flat_map { |item|
        [item[:name], *item[:aliases]].map(&:downcase)
      }.to_set
      print "done!\n"
    end

    def load_nutrition_data
      nutrition_path = File.join(project_root, "resources/nutrition-data.yaml")
      if File.exist?(nutrition_path)
        print "Loading nutrition data..."
        nutrition_data = YAML.safe_load_file(nutrition_path, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
        @nutrition_calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: @omit_set)
        print "done! (#{nutrition_data.size} ingredients.)\n"
      else
        @nutrition_calculator = nil
      end
    end

    def parse_recipes
      if @recipes
        print "Using pre-parsed recipes..."
      else
        print "Parsing recipes from #{recipes_dir}..."
        @recipes = FamilyRecipes.parse_recipes(recipes_dir)
      end
    end

    def parse_quick_bites
      @quick_bites ||= FamilyRecipes.parse_quick_bites(recipes_dir)
      print "done! (#{@recipes.size} recipes, #{@quick_bites.size} quick bites.)\n"
    end

    def build_recipe_map
      @recipe_map = @recipes.to_h { |recipe| [recipe.id, recipe] }
    end

    def validate_cross_references
      print "Validating cross-references..."

      # Validate title/filename slug match
      @recipes.each do |recipe|
        title_slug = FamilyRecipes.slugify(recipe.title)
        if title_slug != recipe.id
          raise StandardError, "Title/filename mismatch: \"#{recipe.title}\" (slug: #{title_slug}) vs filename slug: #{recipe.id}"
        end
      end

      # Validate all cross-references resolve and detect cycles
      @recipes.each do |recipe|
        recipe.cross_references.each do |xref|
          unless @recipe_map.key?(xref.target_slug)
            raise StandardError, "Unresolved cross-reference in \"#{recipe.title}\": @[#{xref.target_title}] (slug: #{xref.target_slug})"
          end
        end
      end

      # Detect circular references via DFS
      @recipes.each do |recipe|
        detect_cycles(recipe, [])
      end

      print "done!\n"
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

    def generate_recipe_pages
      FileUtils.mkdir_p(output_dir)
      print "Generating output files in #{output_dir}..."

      @recipes.each do |recipe|
        text_path = File.join(output_dir, "#{recipe.id}.md")
        FamilyRecipes.write_file_if_changed(text_path, recipe.source)

        nutrition = @nutrition_calculator&.calculate(recipe, @alias_map, @recipe_map)

        template_path = File.join(template_dir, "recipe-template.html.erb")
        html_path = File.join(output_dir, "#{recipe.id}.html")
        FamilyRecipes.write_file_if_changed(html_path, recipe.to_html(erb_template_path: template_path, nutrition: nutrition))
      end

      print "done!\n"
    end

    def copy_resources
      print "Copying web resources from #{resources_dir} to #{output_dir}..."

      Dir.glob(File.join(resources_dir, '**', '*')).each do |source_file|
        next if File.directory?(source_file)

        relative_path = source_file.sub("#{resources_dir}/", '')
        dest_file = File.join(output_dir, relative_path)

        next if File.exist?(dest_file) && FileUtils.identical?(source_file, dest_file)

        FileUtils.mkdir_p(File.dirname(dest_file))
        FileUtils.cp(source_file, dest_file)
        puts "Copied: #{relative_path}"
      end

      print "done!\n"
    end

    def generate_homepage
      print "Generating homepage in #{output_dir}..."

      @recipes_by_category = @recipes.group_by(&:category)
      @quick_bites_by_category = @quick_bites.group_by(&:category)

      homepage_path = File.join(output_dir, "index.html")
      FamilyRecipes.render_template(:homepage, homepage_path,
        grouped_recipes: @recipes_by_category,
        render: render,
        slugify: FamilyRecipes.method(:slugify)
      )

      print "done!\n"
    end

    def generate_index
      print "Generating index..."

      recipes_by_ingredient = @recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
        recipe.all_ingredients(@alias_map).each do |ingredient|
          index[ingredient.normalized_name(@alias_map)] << recipe
        end
      end
      sorted_ingredients = recipes_by_ingredient.sort_by { |name, _| name.downcase }

      index_path = File.join(output_dir, "index", "index.html")
      FamilyRecipes.render_template(:index, index_path,
        sorted_ingredients: sorted_ingredients,
        render: render
      )

      print "done!\n"
    end

    def validate_ingredients
      print "Validating ingredients..."

      ingredients_to_recipes = Hash.new { |h, k| h[k] = [] }
      @recipes.each do |recipe|
        recipe.all_ingredients.each do |ingredient|
          ingredients_to_recipes[ingredient.name] << recipe.title
        end
      end
      @quick_bites.each do |quick_bite|
        quick_bite.ingredients.each do |ingredient_name|
          ingredients_to_recipes[ingredient_name] << quick_bite.title
        end
      end

      unknown_ingredients = ingredients_to_recipes.keys.reject { |name| @known_ingredients.include?(name.downcase) }.to_set
      if unknown_ingredients.any?
        puts "\n"
        puts "WARNING: The following ingredients are not in grocery-info.yaml:"
        unknown_ingredients.sort.each do |ing|
          recipes = ingredients_to_recipes[ing].uniq.sort
          puts "  - #{ing} (in: #{recipes.join(', ')})"
        end
        puts "Add them to grocery-info.yaml or add as aliases to existing items."
        puts ""
      else
        print "done! (All ingredients validated.)\n"
      end
    end

    def validate_nutrition
      return unless @nutrition_calculator

      print "Validating nutrition data..."

      ingredients_to_recipes = @recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
        recipe.all_ingredient_names(@alias_map).each do |name|
          index[name] << recipe.title unless @omit_set.include?(name.downcase)
        end
      end

      # Category 1: Missing nutrition data (no YAML entry at all)
      missing = ingredients_to_recipes.keys.reject { |name| @nutrition_calculator.nutrition_data.key?(name) }

      # Category 2: Missing unit conversions (entry exists, but unit can't be resolved)
      unresolvable = Hash.new { |h, k| h[k] = { units: Set.new, recipes: [] } }
      # Category 3: Unquantified ingredients (listed without a quantity, not counted)
      unquantified = Hash.new { |h, k| h[k] = [] }
      @recipes.each do |recipe|
        recipe.all_ingredients_with_quantities(@alias_map, @recipe_map).each do |name, amounts|
          next if @omit_set.include?(name.downcase)
          entry = @nutrition_calculator.nutrition_data[name]
          next unless entry

          non_nil_amounts = amounts.compact
          unquantified[name] |= [recipe.title] if non_nil_amounts.empty?

          non_nil_amounts.each do |value, unit|
            next if value.nil?

            unless @nutrition_calculator.resolvable?(value, unit, entry)
              info = unresolvable[name]
              info[:units] << (unit || '(bare count)')
              info[:recipes] |= [recipe.title]
            end
          end
        end
      end

      has_warnings = missing.any? || unresolvable.any? || unquantified.any?

      if missing.any?
        puts "\n"
        puts "WARNING: Missing nutrition data:"
        missing.sort.each do |name|
          recipes = ingredients_to_recipes[name].uniq.sort
          puts "  - #{name} (in: #{recipes.join(', ')})"
        end
      end

      if unresolvable.any?
        puts "\n" unless missing.any?
        puts "WARNING: Missing unit conversions:"
        unresolvable.sort_by { |name, _| name }.each do |name, info|
          recipes = info[:recipes].sort
          units = info[:units].to_a.sort.join(', ')
          puts "  - #{name}: '#{units}' (in: #{recipes.join(', ')})"
        end
      end

      if unquantified.any?
        puts "\n" unless missing.any? || unresolvable.any?
        puts "NOTE: Unquantified ingredients (not counted in nutrition):"
        unquantified.sort_by { |name, _| name }.each do |name, recipes|
          puts "  - #{name} (in: #{recipes.sort.join(', ')})"
        end
      end

      if has_warnings
        puts ""
        puts "Use bin/nutrition-entry to add data, or edit resources/nutrition-data.yaml directly."
        puts ""
      else
        print "done! (All ingredients have nutrition data.)\n"
      end
    end

    def generate_groceries_page
      print "Generating groceries page..."

      quick_bites_category = CONFIG[:quick_bites_category]

      grocery_info = @grocery_aisles.transform_values do |items|
        items.map { |item| { name: item[:name] } }
      end

      combined = @recipes_by_category.merge(@quick_bites_by_category)

      regular_recipes = combined.reject { |cat, _| cat.start_with?(quick_bites_category) }
      grocery_quick_bites = combined.select { |cat, _| cat.start_with?(quick_bites_category) }

      quick_bites_prefix = /^#{Regexp.escape(quick_bites_category)}(: )?/
      quick_bites_by_subsection = grocery_quick_bites.transform_keys do |cat|
        name = cat.sub(quick_bites_prefix, '')
        name.empty? ? 'Other' : name
      end

      groceries_path = File.join(output_dir, "groceries", "index.html")
      FamilyRecipes.render_template(:groceries, groceries_path,
        regular_recipes: regular_recipes,
        quick_bites_by_subsection: quick_bites_by_subsection,
        ingredient_database: grocery_info,
        alias_map: @alias_map,
        omitted_ingredients: @omit_set,
        recipe_map: @recipe_map,
        render: render
      )

      print "done!\n"
    end
  end
end
