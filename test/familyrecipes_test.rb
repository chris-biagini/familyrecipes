require_relative 'test_helper'

class FamilyRecipesTest < Minitest::Test
  def test_slugify_simple_word
    assert_equal "cookies", FamilyRecipes.slugify("Cookies")
  end

  def test_slugify_multiple_words
    assert_equal "chocolate-chip-cookies", FamilyRecipes.slugify("Chocolate Chip Cookies")
  end

  def test_slugify_removes_special_characters
    assert_equal "mac--cheese", FamilyRecipes.slugify("Mac & Cheese")
  end

  def test_slugify_handles_accented_characters
    # NFKD normalization decomposes é into e + combining accent, accent is removed
    assert_equal "sauteed-asparagus", FamilyRecipes.slugify("Sautéed Asparagus")
  end

  def test_slugify_removes_parentheses
    assert_equal "sugar-brown", FamilyRecipes.slugify("Sugar (brown)")
  end

  def test_slugify_collapses_multiple_spaces
    assert_equal "red-beans-and-rice", FamilyRecipes.slugify("Red  Beans   and   Rice")
  end

  def test_config_has_quick_bites_filename
    assert_equal 'Quick Bites.md', FamilyRecipes::CONFIG[:quick_bites_filename]
  end

  def test_config_has_templates
    templates = FamilyRecipes::CONFIG[:templates]

    assert_equal 'recipe-template.html.erb', templates[:recipe]
    assert_equal 'homepage-template.html.erb', templates[:homepage]
    assert_equal 'index-template.html.erb', templates[:index]
    assert_equal 'groceries-template.html.erb', templates[:groceries]
  end

  def test_render_partial_raises_without_template_dir
    original_dir = FamilyRecipes.template_dir
    FamilyRecipes.template_dir = nil

    error = assert_raises(RuntimeError) do
      FamilyRecipes.render_partial('head', title: 'Test')
    end

    assert_includes error.message, "template_dir not set"
  ensure
    FamilyRecipes.template_dir = original_dir
  end

  def test_render_template_raises_for_unknown_template
    error = assert_raises(RuntimeError) do
      FamilyRecipes.render_template(:nonexistent, '/tmp/output.html', {})
    end

    assert_includes error.message, "Unknown template"
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
      assert_includes result.keys, "Produce"
      assert_includes result.keys, "Dairy"

      # Check simple item
      apples = result["Produce"].find { |i| i[:name] == "Apples" }
      assert_equal [], apples[:aliases]

      # Check item with aliases
      cheese = result["Dairy"].find { |i| i[:name] == "Cheese" }
      assert_includes cheese[:aliases], "Cheddar cheese"
      assert_includes cheese[:aliases], "Swiss cheese"
    end
  end

  def test_build_alias_map
    grocery_aisles = {
      "Produce" => [
        { name: "Apples", aliases: ["Granny Smith apples", "Gala apples"] }
      ]
    }

    alias_map = FamilyRecipes.build_alias_map(grocery_aisles)

    # Canonical name downcased maps to canonical
    assert_equal "Apples", alias_map["apples"]

    # Direct aliases (downcased) should map to canonical
    assert_equal "Apples", alias_map["granny smith apples"]
    assert_equal "Apples", alias_map["gala apples"]

    # Singular (downcased) should map to canonical
    assert_equal "Apples", alias_map["apple"]
  end

  def test_build_known_ingredients
    grocery_aisles = {
      "Produce" => [
        { name: "Apples", aliases: ["Gala apples"] }
      ]
    }
    alias_map = { "gala apples" => "Apples", "apple" => "Apples" }

    known = FamilyRecipes.build_known_ingredients(grocery_aisles, alias_map)

    assert_includes known, "apples"
    assert_includes known, "gala apples"
    assert_includes known, "apple"
  end

  def test_write_file_if_changed_writes_new_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'new-file.txt')

      FamilyRecipes.write_file_if_changed(path, "Hello, world!")

      assert File.exist?(path)
      assert_equal "Hello, world!", File.read(path)
    end
  end

  def test_write_file_if_changed_skips_unchanged
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'existing.txt')
      File.write(path, "Original content")
      original_mtime = File.mtime(path)

      sleep 0.01 # Ensure time passes

      FamilyRecipes.write_file_if_changed(path, "Original content")

      # File should not have been modified
      assert_equal original_mtime, File.mtime(path)
    end
  end

  def test_write_file_if_changed_updates_changed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'existing.txt')
      File.write(path, "Original content")

      FamilyRecipes.write_file_if_changed(path, "New content")

      assert_equal "New content", File.read(path)
    end
  end
end
