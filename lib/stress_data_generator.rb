# frozen_string_literal: true

# Generates realistic test data for performance stress testing. Creates a
# kitchen with configurable recipe count, ingredient catalog, meal plan state,
# and cook history. Data is plausible (real-looking titles, varied ingredients)
# because HTML size and rendering cost depend on content length.
#
# Collaborators:
# - MarkdownImporter: creates recipes from markdown via the standard write path
# - Kitchen.finalize_writes: runs reconciliation after batch creation
class StressDataGenerator # rubocop:disable Metrics/ClassLength
  CATEGORIES = %w[Breakfast Lunch Dinner Snacks Sides Soups Salads Desserts
                  Appetizers Drinks Baking Sauces].freeze

  TAGS = %w[quick easy vegetarian vegan gluten-free dairy-free spicy comfort
            healthy meal-prep one-pot weeknight holiday batch summer winter
            kid-friendly budget grill fermented].freeze

  PROTEINS = %w[chicken beef pork salmon shrimp tofu tempeh eggs turkey lamb
                cod tilapia tuna sausage bacon ham].freeze

  PRODUCE = %w[onion garlic tomatoes celery potatoes spinach broccoli mushrooms
               zucchini corn lettuce cucumber avocado lemon lime ginger
               cilantro parsley basil thyme rosemary].freeze

  PANTRY = %w[butter flour sugar salt rice pasta bread tortillas vinegar honey
              milk cream cheese yogurt vanilla paprika cumin oregano cinnamon
              cornstarch].freeze

  COMPOUND_INGREDIENTS = {
    'bell pepper' => 'Produce', 'carrots' => 'Produce', 'green beans' => 'Produce',
    'jalapeño' => 'Produce', 'olive oil' => 'Oils & Vinegar', 'black pepper' => 'Spices',
    'chicken broth' => 'Canned Goods', 'soy sauce' => 'Condiments',
    'canned tomatoes' => 'Canned Goods', 'coconut milk' => 'International',
    'baking powder' => 'Baking', 'chili powder' => 'Spices',
    'brown sugar' => 'Baking', 'maple syrup' => 'Condiments'
  }.freeze

  ALL_INGREDIENTS = (PROTEINS + PRODUCE + PANTRY + COMPOUND_INGREDIENTS.keys).freeze

  UNITS = %w[cup cups tbsp tsp oz lb cloves bunch can large medium small piece slices handful].freeze

  ADJECTIVES = %w[Simple Quick Easy Classic Rustic Homestyle Savory Sweet Crispy
                  Creamy Spicy Tangy Smoky Fresh Light Hearty Golden Roasted
                  Grilled Braised].freeze

  NOUNS = %w[Bowl Skillet Bake Stew Soup Salad Wrap Sandwich Pasta Rice Tacos
             Curry Casserole Pie Bread Muffins Pancakes Hash Frittata Risotto
             Chili Noodles Burrito Platter].freeze

  AISLES = ['Produce', 'Dairy', 'Meat & Seafood', 'Bakery', 'Canned Goods',
            'Pasta & Rice', 'Spices', 'Oils & Vinegar', 'Snacks', 'Frozen',
            'Beverages', 'Baking', 'Condiments', 'International', 'Deli'].freeze

  attr_reader :kitchen, :recipe_count

  def initialize(recipe_count: 200)
    @recipe_count = recipe_count
    @used_titles = Set.new
  end

  def generate!
    setup_kitchen
    create_categories
    create_catalog_entries
    create_recipes
    create_meal_plan_state
    create_cook_history
    ActsAsTenant.with_tenant(kitchen) { Kitchen.finalize_writes(kitchen) }
    print_summary
  end

  private

  def setup_kitchen
    ActsAsTenant.without_tenant do
      existing = Kitchen.find_by(slug: 'stress-kitchen')
      ActsAsTenant.with_tenant(existing) { existing.destroy } if existing
    end

    @kitchen = ActsAsTenant.without_tenant do
      Kitchen.create!(slug: 'stress-kitchen', name: 'Stress Kitchen',
                      aisle_order: AISLES.join("\n"))
    end
  end

  def create_categories
    ActsAsTenant.with_tenant(kitchen) do
      CATEGORIES.each_with_index do |name, i|
        Category.find_or_create_for(kitchen, name).update!(position: i)
      end
    end
  end

  def create_catalog_entries
    ActsAsTenant.with_tenant(kitchen) do
      ALL_INGREDIENTS.each_with_index do |name, i|
        IngredientCatalog.create!(catalog_attrs(name, i))
      end
    end
  end

  def catalog_attrs(name, index)
    {
      ingredient_name: name, aisle: aisle_for(name, index), kitchen: kitchen,
      basis_grams: 100, calories: rand(20..400),
      fat: rand(0.0..30.0).round(1), saturated_fat: rand(0.0..15.0).round(1),
      cholesterol: rand(0..120), sodium: rand(0..1200),
      carbs: rand(0.0..60.0).round(1), fiber: rand(0.0..10.0).round(1),
      total_sugars: rand(0.0..20.0).round(1), protein: rand(0.0..40.0).round(1)
    }
  end

  def aisle_for(name, index)
    COMPOUND_INGREDIENTS[name] || AISLES[index % AISLES.size]
  end

  def create_recipes
    categories = ActsAsTenant.with_tenant(kitchen) { Category.all.to_a }

    ActsAsTenant.with_tenant(kitchen) do
      Kitchen.batch_writes(kitchen) do
        recipe_count.times do |i|
          import_one_recipe(categories[i % categories.size])
          print '.' if (i % 20).zero?
        end
      end
    end
    puts
  end

  def import_one_recipe(category)
    tags = TAGS.sample(rand(1..4))
    markdown = build_markdown(title: unique_title, tags:,
                              step_count: rand(1..4),
                              ingredients_per_step: rand(3..8))
    MarkdownImporter.import(markdown, kitchen:, category:)
  end

  def create_meal_plan_state
    ActsAsTenant.with_tenant(kitchen) do
      MealPlan.find_or_create_by!(kitchen:)
      create_selections
      create_on_hand_entries
      create_custom_grocery_items
    end
  end

  def create_selections
    kitchen.recipes.limit(15).pluck(:slug).each do |slug|
      MealPlanSelection.create!(kitchen:, selectable_type: 'Recipe', selectable_id: slug)
    end
  end

  def create_on_hand_entries
    names = all_ingredient_names.sample([all_ingredient_names.size, 200].min)

    names.each_with_index do |name, i|
      entry = OnHandEntry.create!(on_hand_attrs(name))
      next unless (i % 5).zero?

      entry.update_columns(depleted_at: Date.current - rand(0..3)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def on_hand_attrs(name)
    {
      kitchen:, ingredient_name: name,
      confirmed_at: Date.current - rand(0..90),
      interval: rand(OnHandEntry::STARTING_INTERVAL..OnHandEntry::MAX_INTERVAL),
      ease: rand(OnHandEntry::MIN_EASE..OnHandEntry::MAX_EASE).round(2)
    }
  end

  def all_ingredient_names
    @all_ingredient_names ||= kitchen.recipes
                                     .includes(steps: :ingredients)
                                     .flat_map { |r| r.steps.flat_map(&:ingredients) }
                                     .map(&:name).uniq
  end

  def create_custom_grocery_items
    8.times do |i|
      CustomGroceryItem.create!(
        kitchen:, name: "Custom Item #{i + 1}",
        aisle: AISLES.sample, last_used_at: Date.current - rand(0..30)
      )
    end
  end

  def create_cook_history
    ActsAsTenant.with_tenant(kitchen) do
      slugs = kitchen.recipes.pluck(:slug)

      180.times do |day|
        next if rand > 0.6

        CookHistoryEntry.create!(kitchen:, recipe_slug: slugs.sample, cooked_at: Time.current - day.days)
      end
    end
  end

  def print_summary
    ActsAsTenant.with_tenant(kitchen) do
      puts "Stress kitchen '#{kitchen.name}' created:"
      puts "  #{recipe_count} recipes across #{CATEGORIES.size} categories"
      puts "  #{kitchen.ingredient_catalog.size} catalog entries"
      puts "  #{kitchen.on_hand_entries.size} on-hand entries"
      puts "  #{kitchen.cook_history_entries.size} cook history entries"
      puts "  #{kitchen.meal_plan_selections.size} meal plan selections"
    end
  end

  def unique_title
    100.times do
      title = "#{ADJECTIVES.sample} #{PROTEINS.sample.capitalize} #{NOUNS.sample}"
      next if @used_titles.include?(title)

      @used_titles.add(title)
      return title
    end
    "Recipe #{@used_titles.size + 1}"
  end

  def build_markdown(title:, tags:, step_count:, ingredients_per_step:)
    lines = ["# #{title}", '']
    lines.push("Tags: #{tags.join(', ')}", '') if tags.any?
    step_count.times { |s| lines.concat(step_lines(s, ingredients_per_step)) }
    lines.join("\n")
  end

  def step_lines(step_num, ingredient_count)
    lines = ["## Step #{step_num + 1}", '']
    ingredient_count.times { lines << "- #{rand(1..4)} #{UNITS.sample} #{ALL_INGREDIENTS.sample}" }
    lines.push('', 'Cook until done. Stir occasionally and season to taste.', '')
  end
end
