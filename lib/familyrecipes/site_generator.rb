# frozen_string_literal: true

module FamilyRecipes
  class SiteGenerator
    def initialize(project_root, recipes: nil, quick_bites: nil)
      @project_root     = project_root
      @recipes_dir      = File.join(project_root, 'recipes')
      @template_dir     = File.join(project_root, 'templates/web')
      @resources_dir    = File.join(project_root, 'resources/web')
      @output_dir       = File.join(project_root, 'output/web')
      @grocery_info_path = File.join(project_root, 'resources/grocery-info.yaml')
      @site_config_path  = File.join(project_root, 'resources/site-config.yaml')
      @recipes     = recipes
      @quick_bites = quick_bites

      FamilyRecipes.template_dir = @template_dir
    end

    def generate
      clean_output
      load_site_config
      load_grocery_info
      load_nutrition_data
      parse_recipes
      parse_quick_bites
      build_recipe_map
      build_validator.validate_cross_references
      generate_recipe_pages
      copy_resources
      generate_homepage
      generate_index
      build_validator.validate_ingredients
      build_validator.validate_nutrition
      generate_groceries_page
    end

    private

    attr_reader :project_root, :recipes_dir, :template_dir, :resources_dir,
                :output_dir, :grocery_info_path, :site_config_path

    def render
      @render ||= ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) }
    end

    def clean_output
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)
    end

    def load_site_config
      print 'Loading site config...'
      @site_config = YAML.safe_load_file(site_config_path, permitted_classes: [], permitted_symbols: [],
                                                           aliases: false)
      print "done!\n"
    end

    def load_grocery_info
      print "Loading grocery info from #{grocery_info_path}..."
      @grocery_aisles = FamilyRecipes.parse_grocery_info(grocery_info_path)
      @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
      @known_ingredients = FamilyRecipes.build_known_ingredients(@grocery_aisles, @alias_map)
      @omit_set = (@grocery_aisles['Omit_From_List'] || []).flat_map do |item|
        [item[:name], *item[:aliases]].map(&:downcase)
      end.to_set
      print "done!\n"
    end

    def load_nutrition_data
      nutrition_path = File.join(project_root, 'resources/nutrition-data.yaml')
      if File.exist?(nutrition_path)
        print 'Loading nutrition data...'
        nutrition_data = YAML.safe_load_file(nutrition_path, permitted_classes: [], permitted_symbols: [],
                                                             aliases: false) || {}
        @nutrition_calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: @omit_set)
        print "done! (#{nutrition_data.size} ingredients.)\n"
      else
        @nutrition_calculator = nil
      end
    end

    def parse_recipes
      if @recipes
        print 'Using pre-parsed recipes...'
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

    def build_validator
      @build_validator ||= BuildValidator.new(
        recipes: @recipes,
        quick_bites: @quick_bites,
        recipe_map: @recipe_map,
        alias_map: @alias_map,
        known_ingredients: @known_ingredients,
        omit_set: @omit_set,
        nutrition_calculator: @nutrition_calculator
      )
    end

    def generate_recipe_pages
      print "Generating output files in #{output_dir}..."

      @recipes.each do |recipe|
        text_path = File.join(output_dir, "#{recipe.id}.md")
        File.write(text_path, recipe.source)

        nutrition = @nutrition_calculator&.calculate(recipe, @alias_map, @recipe_map)

        template_path = File.join(template_dir, 'recipe-template.html.erb')
        html_path = File.join(output_dir, "#{recipe.id}.html")
        File.write(html_path, recipe.to_html(erb_template_path: template_path, nutrition: nutrition))
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

      homepage_path = File.join(output_dir, 'index.html')
      FamilyRecipes.render_template(:homepage, homepage_path,
                                    grouped_recipes: @recipes_by_category,
                                    site_config: @site_config,
                                    render: render,
                                    slugify: FamilyRecipes.method(:slugify))

      print "done!\n"
    end

    def generate_index
      print 'Generating index...'

      recipes_by_ingredient = @recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
        recipe.all_ingredients(@alias_map).each do |ingredient|
          index[ingredient.normalized_name(@alias_map)] << recipe
        end
      end
      sorted_ingredients = recipes_by_ingredient.sort_by { |name, _| name.downcase }

      index_path = File.join(output_dir, 'index', 'index.html')
      FamilyRecipes.render_template(:index, index_path,
                                    sorted_ingredients: sorted_ingredients,
                                    site_config: @site_config,
                                    render: render)

      print "done!\n"
    end

    def generate_groceries_page
      print 'Generating groceries page...'

      quick_bites_category = CONFIG[:quick_bites_category]

      grocery_info = @grocery_aisles.transform_values do |items|
        items.map { |item| { name: item[:name] } }
      end

      unit_plurals = collect_unit_plurals

      combined = @recipes_by_category.merge(@quick_bites_by_category)

      regular_recipes = combined.reject { |cat, _| cat.start_with?(quick_bites_category) }
      grocery_quick_bites = combined.select { |cat, _| cat.start_with?(quick_bites_category) }

      quick_bites_prefix = /^#{Regexp.escape(quick_bites_category)}(: )?/
      quick_bites_by_subsection = grocery_quick_bites.transform_keys do |cat|
        name = cat.sub(quick_bites_prefix, '')
        name.empty? ? 'Other' : name
      end

      groceries_path = File.join(output_dir, 'groceries', 'index.html')
      FamilyRecipes.render_template(:groceries, groceries_path,
                                    regular_recipes: regular_recipes,
                                    quick_bites_by_subsection: quick_bites_by_subsection,
                                    site_config: @site_config,
                                    ingredient_database: grocery_info,
                                    alias_map: @alias_map,
                                    omitted_ingredients: @omit_set,
                                    recipe_map: @recipe_map,
                                    render: render,
                                    unit_plurals: unit_plurals)

      print "done!\n"
    end

    def collect_unit_plurals
      @recipes
        .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
        .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
        .uniq
        .to_h { |u| [u, Inflector.unit_display(u, 2)] }
    end
  end
end
