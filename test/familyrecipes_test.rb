# frozen_string_literal: true

require_relative 'test_helper'

class FamilyRecipesTest < Minitest::Test
  def test_slugify_simple_word
    assert_equal 'cookies', FamilyRecipes.slugify('Cookies')
  end

  def test_slugify_multiple_words
    assert_equal 'chocolate-chip-cookies', FamilyRecipes.slugify('Chocolate Chip Cookies')
  end

  def test_slugify_removes_special_characters
    assert_equal 'mac--cheese', FamilyRecipes.slugify('Mac & Cheese')
  end

  def test_slugify_handles_accented_characters
    # NFKD normalization decomposes é into e + combining accent, accent is removed
    assert_equal 'sauteed-asparagus', FamilyRecipes.slugify('Sautéed Asparagus')
  end

  def test_slugify_removes_parentheses
    assert_equal 'sugar-brown', FamilyRecipes.slugify('Sugar (brown)')
  end

  def test_slugify_collapses_multiple_spaces
    assert_equal 'red-beans-and-rice', FamilyRecipes.slugify('Red  Beans   and   Rice')
  end

  def test_parse_grocery_info_returns_aisles
    # Create a temp YAML file for testing
    yaml_content = <<~YAML
      Produce:
        - Apples
        - Bananas
      Dairy:
        - name: Cheese
          aliases:
            - Cheddar cheese
            - Swiss cheese
    YAML

    Dir.mktmpdir do |dir|
      yaml_path = File.join(dir, 'test-grocery.yaml')
      File.write(yaml_path, yaml_content)

      result = FamilyRecipes.parse_grocery_info(yaml_path)

      assert_equal 2, result.keys.length
      assert_includes result.keys, 'Produce'
      assert_includes result.keys, 'Dairy'

      # Check simple item
      apples = result['Produce'].find { |i| i[:name] == 'Apples' }

      assert_empty apples[:aliases]

      # Check item with aliases
      cheese = result['Dairy'].find { |i| i[:name] == 'Cheese' }

      assert_includes cheese[:aliases], 'Cheddar cheese'
      assert_includes cheese[:aliases], 'Swiss cheese'
    end
  end

  def test_build_alias_map
    grocery_aisles = {
      'Produce' => [
        { name: 'Apples', aliases: ['Granny Smith apples', 'Gala apples'] }
      ]
    }

    alias_map = FamilyRecipes.build_alias_map(grocery_aisles)

    # Canonical name downcased maps to canonical
    assert_equal 'Apples', alias_map['apples']

    # Direct aliases (downcased) should map to canonical
    assert_equal 'Apples', alias_map['granny smith apples']
    assert_equal 'Apples', alias_map['gala apples']

    # Singular forms (downcased) should map to canonical
    assert_equal 'Apples', alias_map['apple']
    assert_equal 'Apples', alias_map['granny smith apple']
    assert_equal 'Apples', alias_map['gala apple']
  end

  def test_build_known_ingredients
    grocery_aisles = {
      'Produce' => [
        { name: 'Apples', aliases: ['Gala apples'] }
      ]
    }
    alias_map = { 'gala apples' => 'Apples', 'apple' => 'Apples', 'gala apple' => 'Apples' }

    known = FamilyRecipes.build_known_ingredients(grocery_aisles, alias_map)

    assert_includes known, 'apples'
    assert_includes known, 'gala apples'
    assert_includes known, 'apple'
    assert_includes known, 'gala apple'
  end

  def test_parse_grocery_aisles_markdown_basic
    content = <<~MD
      ## Produce
      - Apples
      - Bananas

      ## Baking
      - Flour
    MD

    result = FamilyRecipes.parse_grocery_aisles_markdown(content)

    assert_equal %w[Produce Baking], result.keys
    assert_equal 'Apples', result['Produce'].first[:name]
    assert_equal 'Bananas', result['Produce'].last[:name]
    assert_equal 'Flour', result['Baking'].first[:name]
  end

  def test_parse_grocery_aisles_markdown_omit_from_list
    content = <<~MD
      ## Produce
      - Garlic

      ## Omit From List
      - Water
      - Sourdough starter
    MD

    result = FamilyRecipes.parse_grocery_aisles_markdown(content)

    assert_equal ['Produce', 'Omit From List'], result.keys
    assert_equal 'Water', result['Omit From List'].first[:name]
  end

  def test_parse_grocery_aisles_markdown_ignores_non_list_lines
    content = <<~MD
      # Grocery Aisles

      Some description text.

      ## Produce
      - Apples

      Random text between aisles.

      ## Baking
      - Flour
    MD

    result = FamilyRecipes.parse_grocery_aisles_markdown(content)

    assert_equal %w[Produce Baking], result.keys
  end

  def test_parse_quick_bites_content
    content = <<~MD
      # Quick Bites

      ## Snacks
        - Peanut Butter on Bread: Peanut butter, Bread
        - Goldfish

      ## Breakfast
        - Cereal with Milk: Cereal, Milk
    MD

    result = FamilyRecipes.parse_quick_bites_content(content)

    assert_equal 3, result.size
    assert_equal 'Peanut Butter on Bread', result[0].title
    assert_equal ['Peanut butter', 'Bread'], result[0].ingredients
    assert_equal 'Quick Bites: Snacks', result[0].category
    assert_equal 'Goldfish', result[1].title
    assert_equal ['Goldfish'], result[1].ingredients
    assert_equal 'Quick Bites: Breakfast', result[2].category
  end

  def test_build_alias_map_without_aliases
    grocery_aisles = {
      'Produce' => [{ name: 'Apples' }]
    }

    alias_map = FamilyRecipes.build_alias_map(grocery_aisles)

    assert_equal 'Apples', alias_map['apples']
    assert_equal 'Apples', alias_map['apple']
  end
end
