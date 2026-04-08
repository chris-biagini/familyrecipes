# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'yaml'
require_relative '../../scripts/seed_catalog/shared'

class SeedCatalogSharedTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)

  def test_parse_ingredient_list
    path = File.join(FIXTURES, 'sample_ingredient_list.md')
    result = SeedCatalog.parse_ingredient_list(path)

    assert_equal 5, result.size
    assert_equal 'Apples', result[0][:name]
    assert_equal 'Produce', result[0][:category]
    assert_equal 'Milk', result[4][:name]
    assert_equal 'Dairy & Eggs', result[4][:category]
  end

  def test_parse_ingredient_list_skips_blank_lines_and_prose
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, <<~MD)
        # Ingredient List

        Some intro text that should be ignored.

        ## Produce
        - Apples

        - Carrots
      MD

      result = SeedCatalog.parse_ingredient_list(path)

      assert_equal 2, result.size
      assert_equal 'Apples', result[0][:name]
      assert_equal 'Carrots', result[1][:name]
    end
  end

  def test_json_round_trip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.json')
      data = [{ 'name' => 'Butter', 'category' => 'Dairy' }]

      SeedCatalog.write_json(path, data)
      result = SeedCatalog.read_json(path)

      assert_equal data, result
    end
  end

  def test_read_json_returns_empty_array_for_missing_file
    result = SeedCatalog.read_json('/nonexistent/path.json')

    assert_empty result
  end

  def test_build_catalog_entry
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated',
                                                    aliases: ['Sweet cream butter'])

    assert_in_delta 100.0, entry['nutrients']['basis_grams']
    assert_in_delta 717.0, entry['nutrients']['calories']
    assert_in_delta 81.11, entry['nutrients']['fat']

    source = entry['sources'].first

    assert_equal 'usda', source['type']
    assert_equal 'SR Legacy', source['dataset']
    assert_equal 173_430, source['fdc_id']
    assert_equal 'Butter, without salt', source['description']

    assert_equal 'Refrigerated', entry['aisle']
    assert_equal ['Sweet cream butter'], entry['aliases']

    assert entry.key?('density'), 'Expected density from cup portion'
    assert_equal 'cup', entry['density']['unit']
    assert_in_delta 1.0, entry['density']['volume']
    assert_in_delta 227.0, entry['density']['grams']
  end

  def test_build_catalog_entry_omits_empty_aliases
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated', aliases: [])

    refute entry.key?('aliases')
  end

  def test_build_catalog_entry_produces_valid_yaml
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated', aliases: [])

    catalog = { 'Butter (unsalted)' => entry }
    yaml_str = YAML.dump(catalog)
    roundtripped = YAML.safe_load(yaml_str)

    assert_equal entry['nutrients']['calories'],
                 roundtripped['Butter (unsalted)']['nutrients']['calories']
    assert_equal 'usda', roundtripped['Butter (unsalted)']['sources'].first['type']
  end

  private

  def load_fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")), symbolize_names: true)
  end
end
