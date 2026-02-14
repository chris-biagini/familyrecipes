module FamilyRecipes
  class PdfGenerator
    def initialize(project_root)
      @project_root      = project_root
      @recipes_dir       = File.join(project_root, "recipes")
      @template_dir      = File.join(project_root, "templates/pdf")
      @resources_dir     = File.join(project_root, "resources/pdf")
      @output_dir        = File.join(project_root, "output/pdf")
      @grocery_info_path = File.join(project_root, "resources/grocery-info.yaml")
    end

    def generate
      load_ingredient_aliases
      parse_recipes
      parse_quick_bites
      build_ingredient_index
      render_typst
      compile_pdf
    end

    private

    def load_ingredient_aliases
      grocery_aisles = FamilyRecipes.parse_grocery_info(@grocery_info_path)
      alias_map = FamilyRecipes.build_alias_map(grocery_aisles)
      Ingredient.alias_map = alias_map
    end

    def parse_recipes
      print "PDF: Parsing recipes..."

      quick_bites_filename = CONFIG[:quick_bites_filename]

      recipe_files = Dir.glob(File.join(@recipes_dir, "**", "*")).select do |file|
        File.file?(file) && File.basename(file) != quick_bites_filename
      end

      @recipes = recipe_files.map do |file|
        source = File.read(file)
        id = FamilyRecipes.slugify(File.basename(file, ".*"))
        category = File.basename(File.dirname(file)).sub(/^./, &:upcase)
        Recipe.new(markdown_source: source, id: id, category: category)
      end

      @recipes_by_category = @recipes
        .group_by(&:category)
        .sort_by { |cat, _| cat }
        .to_h
      @recipes_by_category.each_value { |recipes| recipes.sort_by!(&:title) }
    end

    def parse_quick_bites
      quick_bites_filename = CONFIG[:quick_bites_filename]
      quick_bites_category = CONFIG[:quick_bites_category]
      file_path = File.join(@recipes_dir, quick_bites_filename)

      quick_bite_specs = []
      current_subcat = nil

      File.foreach(file_path) do |line|
        case line
        when /^##\s+(.*)/
          current_subcat = $1.strip
        when /^\s*-\s+(.*)/
          text = $1.strip
          category = [quick_bites_category, current_subcat].compact.join(": ")
          quick_bite_specs << { text: text, category: category }
        end
      end

      @quick_bites = quick_bite_specs.map do |spec|
        QuickBite.new(text_source: spec[:text], category: spec[:category])
      end

      quick_bites_prefix = /^#{Regexp.escape(quick_bites_category)}(: )?/
      @quick_bites_by_category = @quick_bites
        .group_by(&:category)
        .transform_keys { |cat| cat.sub(quick_bites_prefix, '').then { |n| n.empty? ? 'Other' : n } }

      print "done! (#{@recipes.size} recipes, #{@quick_bites.size} quick bites)\n"
    end

    def build_ingredient_index
      index = Hash.new { |h, k| h[k] = [] }
      @recipes.each do |recipe|
        recipe.all_ingredients.each do |ingredient|
          index[ingredient.normalized_name] << recipe
        end
      end

      @ingredient_index = index
        .sort_by { |name, _| name.downcase }
        .map { |name, recipes| [name, recipes.uniq(&:id).sort_by(&:title)] }
    end

    def render_typst
      print "PDF: Rendering Typst source..."

      template_path = File.join(@template_dir, "cookbook.typ.erb")
      template = ERB.new(File.read(template_path), trim_mode: '-')

      @typst_content = template.result_with_hash(
        recipes_by_category: @recipes_by_category,
        quick_bites_by_category: @quick_bites_by_category,
        ingredient_index: @ingredient_index,
        typst_escape: method(:typst_escape),
        typst_prose: method(:typst_prose)
      )

      print "done!\n"
    end

    def compile_pdf
      unless system("which typst > /dev/null 2>&1")
        puts "PDF: WARNING — typst CLI not found. Skipping PDF compilation."
        puts "     Install Typst (https://typst.app) to generate cookbook.pdf."
        return
      end

      print "PDF: Compiling cookbook.pdf..."

      FileUtils.mkdir_p(@output_dir)
      font_path = File.join(@resources_dir, "fonts")
      pdf_path = File.join(@output_dir, "cookbook.pdf")

      Tempfile.create(['cookbook', '.typ']) do |typst_file|
        typst_file.write(@typst_content)
        typst_file.flush

        success = system("typst", "compile", "--font-path", font_path, typst_file.path, pdf_path)
        if success
          print "done!\n"
          puts "PDF: Generated #{pdf_path}"
        else
          puts "\nPDF: ERROR — typst compile failed."
        end
      end
    end

    # Escape all Typst special characters (for titles, ingredient names, etc.)
    def typst_escape(text)
      return '' if text.nil?
      text.gsub(/[#*_`$@<>~\\]/) { |c| "\\#{c}" }
    end

    # Escape Typst special characters in prose, preserving _ for emphasis
    # and converting markdown links [text](url) to Typst #link("url")[text]
    def typst_prose(text)
      return '' if text.nil?

      # Split on markdown links, process each part separately
      parts = text.split(/(\[[^\]]+\]\([^)]+\))/)

      parts.map do |part|
        if part =~ /\A\[([^\]]+)\]\(([^)]+)\)\z/
          # Convert markdown link to Typst link
          "#link(\"#{$2}\")[#{$1}]"
        else
          # Escape special chars but preserve _ for italic
          part.gsub(/[#*`$@<>~\\]/) { |c| "\\#{c}" }
        end
      end.join
    end
  end
end
