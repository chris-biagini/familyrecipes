# frozen_string_literal: true

require 'test_helper'

class ImportServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    @kitchen.recipes.destroy_all
  end

  # --- Individual file import ---

  test 'imports single .md file as recipe in Miscellaneous' do
    result = import_files(uploaded_file('Pancakes.md', simple_recipe('Pancakes')))

    assert_equal 1, result.recipes
    assert @kitchen.recipes.find_by(title: 'Pancakes')
    assert_equal 'Miscellaneous', @kitchen.recipes.find_by(title: 'Pancakes').category.name
  end

  test 'imports multiple individual files' do
    result = import_files(
      uploaded_file('Pancakes.md', simple_recipe('Pancakes')),
      uploaded_file('Waffles.md', simple_recipe('Waffles'))
    )

    assert_equal 2, result.recipes
    assert_equal 2, @kitchen.recipes.count
  end

  test 'accepts .txt and .text extensions' do
    result = import_files(
      uploaded_file('Pancakes.txt', simple_recipe('Pancakes')),
      uploaded_file('Waffles.text', simple_recipe('Waffles'))
    )

    assert_equal 2, result.recipes
  end

  test 'same-title reimport overwrites existing recipe' do
    RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

    result = import_files(uploaded_file('Pancakes.md', simple_recipe('Pancakes')))

    assert_equal 1, result.recipes
    assert_equal 1, @kitchen.recipes.where(title: 'Pancakes').count
  end

  test 'single file import reports collision as error when slug matches different title' do
    RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

    result = import_files(uploaded_file('Pancakes!.md', simple_recipe('Pancakes!')))

    assert_equal 0, result.recipes
    assert_equal 1, result.errors.size
    assert_match(/similar name already exists/, result.errors.first)
    assert_equal 'Pancakes', @kitchen.recipes.find_by(slug: 'pancakes').title
  end

  test 'collects parse errors without aborting' do
    result = import_files(
      uploaded_file('Bad.md', 'not a valid recipe'),
      uploaded_file('Good.md', simple_recipe('Good'))
    )

    assert_equal 1, result.recipes
    assert_equal 1, result.errors.size
    assert_match(/Bad\.md:/, result.errors.first)
  end

  # --- ZIP import ---

  test 'ZIP with category folders creates recipes in correct categories' do
    zip = build_zip(
      'Bread/Focaccia.md' => simple_recipe('Focaccia'),
      'Desserts/Brownies.md' => simple_recipe('Brownies')
    )
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 2, result.recipes
    assert_equal 'Bread', @kitchen.recipes.find_by(title: 'Focaccia').category.name
    assert_equal 'Desserts', @kitchen.recipes.find_by(title: 'Brownies').category.name
  end

  test 'ZIP root-level recipes go to Miscellaneous' do
    zip = build_zip('Pancakes.md' => simple_recipe('Pancakes'))
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.recipes
    assert_equal 'Miscellaneous', @kitchen.recipes.find_by(title: 'Pancakes').category.name
  end

  test 'ZIP skips non-recipe files silently' do
    zip = build_zip(
      '.DS_Store' => 'junk',
      '__MACOSX/stuff' => 'junk',
      'photo.jpg' => 'binary',
      'Bread/Focaccia.md' => simple_recipe('Focaccia')
    )
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.recipes
    assert_empty result.errors
  end

  test 'when ZIP is present, ignores other non-ZIP files' do
    zip = build_zip('Bread/Focaccia.md' => simple_recipe('Focaccia'))
    result = import_files(
      uploaded_file('extra.md', simple_recipe('Extra')),
      uploaded_file('export.zip', zip)
    )

    assert_equal 1, result.recipes
    assert_nil @kitchen.recipes.find_by(title: 'Extra')
  end

  test 'ZIP import skips colliding recipe and reports error' do
    RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

    zip = build_zip('Bread/Pancakes!.md' => simple_recipe('Pancakes!'))
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 0, result.recipes
    assert_equal 1, result.errors.size
    assert_match(/similar name already exists/, result.errors.first)
  end

  test 'ZIP with internal slug collision skips second file and reports error' do
    zip = build_zip(
      'Bread/Cookies.md' => simple_recipe('Cookies'),
      'Desserts/Cookies!.md' => simple_recipe('Cookies!')
    )
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.recipes
    assert_equal 1, result.errors.size
    assert_match(/similar name already exists/, result.errors.first)
  end

  # --- Quick Bites ---

  test 'imports Quick Bites from ZIP' do
    zip = build_zip('quick-bites.txt' => "## Snacks\n- Chips\n- Salsa")
    result = import_files(uploaded_file('export.zip', zip))

    assert result.quick_bites
    assert_equal 2, @kitchen.quick_bites.count
    assert_equal %w[Chips Salsa], @kitchen.quick_bites.ordered.map(&:title)
  end

  test 'recognizes Quick Bites filename variants' do
    ['Quick-Bites.md', 'quickbites.text', 'QuickBites.txt', 'quick bites.md'].each do |name|
      zip = build_zip(name => "## Snacks\n- Item")
      result = import_files(uploaded_file('export.zip', zip))

      assert result.quick_bites, "Expected #{name} to be recognized as Quick Bites"
      assert_predicate @kitchen.quick_bites, :exists?, "Expected QBs to exist for #{name}"
    end
  end

  # --- Custom ingredients ---

  test 'imports custom ingredients YAML from ZIP' do
    yaml_content = { 'Special Flour' => { 'aisle' => 'Pantry' } }.to_yaml
    zip = build_zip('custom-ingredients.yaml' => yaml_content)
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.ingredients

    entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Special Flour')

    assert_equal 'Pantry', entry.aisle
    assert_includes @kitchen.reload.parsed_aisle_order, 'Pantry'
  end

  test 'upserts existing ingredient catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Special Flour', aisle: 'Baking')

    yaml_content = { 'Special Flour' => { 'aisle' => 'Pantry' } }.to_yaml
    zip = build_zip('custom-ingredients.yaml' => yaml_content)
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.ingredients
    assert_equal 1, IngredientCatalog.where(kitchen: @kitchen, ingredient_name: 'Special Flour').count
    assert_equal 'Pantry', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Special Flour').aisle
  end

  test 'malformed YAML reports error' do
    zip = build_zip('custom-ingredients.yaml' => ":\ninvalid: [yaml\n")
    result = import_files(uploaded_file('export.zip', zip))

    assert_equal 1, result.errors.size
    assert_match(/custom-ingredients\.yaml/, result.errors.first)
  end

  # --- Aisle order ---

  test 'imports aisle-order.txt from ZIP' do
    zip = build_zip('aisle-order.txt' => "Produce\nBaking\nDairy")
    import_files(uploaded_file('export.zip', zip))

    assert_equal "Produce\nBaking\nDairy", @kitchen.reload.aisle_order
  end

  test 'missing aisle-order.txt is gracefully skipped' do
    zip = build_zip('Bread/Focaccia.md' => simple_recipe('Focaccia'))
    import_files(uploaded_file('export.zip', zip))

    assert_nil @kitchen.reload.aisle_order
  end

  # --- Category order ---

  test 'imports category-order.txt and sets positions after recipe import' do
    zip = build_zip(
      'category-order.txt' => "Desserts\nBread",
      'Bread/Focaccia.md' => simple_recipe('Focaccia'),
      'Desserts/Brownies.md' => simple_recipe('Brownies')
    )
    import_files(uploaded_file('export.zip', zip))

    bread = @kitchen.categories.find_by(name: 'Bread')
    desserts = @kitchen.categories.find_by(name: 'Desserts')

    assert_operator bread.position, :>, desserts.position,
                    "Expected Desserts (#{desserts.position}) before Bread (#{bread.position})"
  end

  test 'missing category-order.txt is gracefully skipped' do
    zip = build_zip('Bread/Focaccia.md' => simple_recipe('Focaccia'))
    import_files(uploaded_file('export.zip', zip))

    assert @kitchen.categories.find_by(name: 'Bread')
  end

  # --- Import ordering: catalog before recipes ---

  test 'recipes imported after catalog get correct nutrition on first pass' do
    create_catalog_entry('Flour', basis_grams: 100, calories: 364, aisle: 'Baking')

    yaml_content = { 'Flour' => { 'aisle' => 'Baking',
                                  'nutrients' => { 'basis_grams' => 30, 'calories' => 110 } } }.to_yaml

    zip = build_zip(
      'custom-ingredients.yaml' => yaml_content,
      'Bread/Focaccia.md' => simple_recipe_with_ingredient('Focaccia', 'Flour', '200 g')
    )
    import_files(uploaded_file('export.zip', zip))

    recipe = @kitchen.recipes.find_by!(title: 'Focaccia')

    assert_not_nil recipe.nutrition_data
    # Custom entry: 110 cal per 30g → 200g = 733.3 cal (not 364 * 2 = 728 from global)
    assert_in_delta 733.3, recipe.nutrition_data['totals']['calories'], 1.0
  end

  # --- Round-trip ---

  test 'export then import into empty kitchen preserves all data' do
    @kitchen.update!(aisle_order: "Produce\nBaking")
    RecipeWriteService.create(markdown: simple_recipe('Round Trip'), kitchen: @kitchen, category_name: 'Dinners')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Test Flour', aisle: 'Baking')
    @kitchen.categories.ordered.each_with_index { |c, i| c.update!(position: i) }

    zip_data = ExportService.call(kitchen: @kitchen)

    # Clear the kitchen
    @kitchen.recipes.destroy_all
    @kitchen.categories.destroy_all
    IngredientCatalog.where(kitchen: @kitchen).delete_all
    @kitchen.update!(aisle_order: nil)

    import_files(uploaded_file('export.zip', zip_data))

    assert_equal "Produce\nBaking", @kitchen.reload.aisle_order
    assert IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Test Flour')
    assert_predicate @kitchen.recipes, :any?
    assert_predicate @kitchen.categories, :any?
  end

  # --- File size limits ---

  test 'rejects file exceeding MAX_FILE_SIZE' do
    huge = 'x' * (ImportService::MAX_FILE_SIZE + 1)
    result = import_files(uploaded_file('huge.md', huge))

    assert_equal 0, result.recipes
    assert(result.errors.any? { |e| e.include?('exceeds') })
  end

  test 'rejects oversized ZIP file' do
    huge = 'x' * (ImportService::MAX_FILE_SIZE + 1)
    result = import_files(uploaded_file('huge.zip', huge))

    assert_equal 0, result.recipes
    assert(result.errors.any? { |e| e.include?('exceeds') })
  end

  # --- ZIP entry count limits ---

  test 'ZIP with too many entries reports error and stops' do
    entries = (1..501).to_h { |i| ["Recipe#{i}.md", simple_recipe("Recipe #{i}")] }
    zip = build_zip(entries)
    result = import_files(uploaded_file('huge.zip', zip))

    assert(result.errors.any? { |e| e.include?('entry limit') })
    assert_operator @kitchen.recipes.count, :<=, ImportService::MAX_ZIP_ENTRIES
  end

  # --- Encoding ---

  test 'handles non-UTF-8 content gracefully' do
    # Latin-1 encoded string with a non-UTF-8 byte
    content = simple_recipe('Cr\xe8me').dup.force_encoding('BINARY')
    result = import_files(uploaded_file('recipe.md', content))

    assert_equal 1, result.recipes
  end

  # --- Batch broadcast ---

  test 'multi-recipe import produces exactly one broadcast' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }

    zip = build_zip(
      'Bread/Focaccia.md' => simple_recipe('Focaccia'),
      'Desserts/Brownies.md' => simple_recipe('Brownies'),
      'Soup/Chowder.md' => simple_recipe('Chowder')
    )
    import_files(uploaded_file('export.zip', zip))

    assert_equal 1, broadcast_count
    assert_equal 3, @kitchen.recipes.count
  end

  private

  def import_files(*file_list)
    ImportService.call(kitchen: @kitchen, files: file_list)
  end

  def uploaded_file(filename, content, content_type: 'text/plain')
    Rack::Test::UploadedFile.new(
      StringIO.new(content), content_type, original_filename: filename
    )
  end

  def build_zip(entries = {})
    buffer = Zip::OutputStream.write_buffer do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    buffer.string
  end

  def simple_recipe(title)
    <<~MD
      # #{title}


      ## Steps

      - Flour, 1 cup

      Do the thing.
    MD
  end

  def simple_recipe_with_ingredient(title, ingredient, quantity)
    <<~MD
      # #{title}


      ## Steps

      - #{ingredient}, #{quantity}

      Do the thing.
    MD
  end
end
