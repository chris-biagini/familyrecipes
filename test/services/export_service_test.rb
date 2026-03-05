# frozen_string_literal: true

require 'test_helper'

class ExportServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Bread')
    Category.find_or_create_by!(name: 'Desserts', slug: 'desserts')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Brownies

      Category: Desserts

      ## Bake

      - Cocoa, 1 cup

      Bake at 350.
    MD
  end

  test 'generates ZIP with recipes organized by category folders' do
    zip_data = ExportService.call(kitchen: @kitchen)
    names = zip_entry_names(zip_data)

    assert_includes names, 'Bread/Focaccia.md'
    assert_includes names, 'Desserts/Brownies.md'
  end

  test 'recipe files contain markdown_source content' do
    zip_data = ExportService.call(kitchen: @kitchen)
    content = zip_entry_content(zip_data, 'Bread/Focaccia.md')
    recipe = @kitchen.recipes.find_by!(title: 'Focaccia')

    assert_equal recipe.markdown_source, content
  end

  test 'includes quick bites when present' do
    @kitchen.update!(quick_bites_content: "Chips\nSalsa")
    zip_data = ExportService.call(kitchen: @kitchen)
    names = zip_entry_names(zip_data)

    assert_includes names, 'quick-bites.txt'
    assert_equal "Chips\nSalsa", zip_entry_content(zip_data, 'quick-bites.txt')
  end

  test 'omits quick bites file when content is blank' do
    @kitchen.update!(quick_bites_content: '')
    zip_data = ExportService.call(kitchen: @kitchen)
    names = zip_entry_names(zip_data)

    assert_not_includes names, 'quick-bites.txt'
  end

  test 'includes custom ingredients as YAML with correct structure' do
    IngredientCatalog.create!(
      kitchen: @kitchen,
      ingredient_name: 'Special Flour',
      aisle: 'Pantry',
      basis_grams: 100.0,
      calories: 350.0,
      density_grams: 143.0,
      density_volume: 1.0,
      density_unit: 'cup',
      portions: { 'slice' => 30.0 },
      aliases: ['Alt name'],
      sources: [{ 'type' => 'usda', 'dataset' => 'SR Legacy' }]
    )

    zip_data = ExportService.call(kitchen: @kitchen)
    names = zip_entry_names(zip_data)

    assert_includes names, 'custom-ingredients.yaml'

    parsed = YAML.safe_load(zip_entry_content(zip_data, 'custom-ingredients.yaml'))
    entry = parsed['Special Flour']

    assert_equal 'Pantry', entry['aisle']
    assert_equal ['Alt name'], entry['aliases']
    assert_in_delta(100.0, entry.dig('nutrients', 'basis_grams'))
    assert_in_delta(350.0, entry.dig('nutrients', 'calories'))
    assert_in_delta(143.0, entry.dig('density', 'grams'))
    assert_in_delta(1.0, entry.dig('density', 'volume'))
    assert_equal 'cup', entry.dig('density', 'unit')
    assert_in_delta(30.0, entry.dig('portions', 'slice'))
    assert_equal 'usda', entry.dig('sources', 0, 'type')
  end

  test 'omits custom ingredients file when none exist' do
    zip_data = ExportService.call(kitchen: @kitchen)
    names = zip_entry_names(zip_data)

    assert_not_includes names, 'custom-ingredients.yaml'
  end

  test 'filename uses kitchen slug and current date' do
    expected = "#{@kitchen.slug}-#{Date.current.iso8601}.zip"

    assert_equal expected, ExportService.filename(kitchen: @kitchen)
  end

  private

  def zip_entry_names(zip_data)
    entries = []
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        entries << entry.name
      end
    end
    entries
  end

  def zip_entry_content(zip_data, name)
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        return zis.read if entry.name == name
      end
    end
  end
end
