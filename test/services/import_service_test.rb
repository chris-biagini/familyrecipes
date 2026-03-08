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
    zip = build_zip('quick-bites.txt' => "Chips\nSalsa")
    result = import_files(uploaded_file('export.zip', zip))

    assert result.quick_bites
    assert_equal "Chips\nSalsa", @kitchen.reload.quick_bites_content
  end

  test 'recognizes Quick Bites filename variants' do
    ['Quick-Bites.md', 'quickbites.text', 'QuickBites.txt', 'quick bites.md'].each do |name|
      zip = build_zip(name => "Snacks v#{name}")
      result = import_files(uploaded_file('export.zip', zip))

      assert result.quick_bites, "Expected #{name} to be recognized as Quick Bites"
      assert_equal "Snacks v#{name}", @kitchen.reload.quick_bites_content
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
end
