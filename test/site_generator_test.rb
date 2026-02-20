# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class SiteGeneratorTest < Minitest::Test
  def setup
    @project_root = File.expand_path('..', __dir__)
    @output_dir = File.join(@project_root, 'output', 'web')
    @recipes_dir = File.join(@project_root, 'recipes')

    FamilyRecipes::SiteGenerator.new(@project_root).generate
  end

  def test_generate_produces_expected_output_files
    assert_path_exists File.join(@output_dir, 'index.html'), 'homepage should exist'
    assert_path_exists File.join(@output_dir, 'index', 'index.html'), 'ingredient index should exist'
    assert_path_exists File.join(@output_dir, 'groceries', 'index.html'), 'groceries page should exist'
    assert_path_exists File.join(@output_dir, 'style.css'), 'stylesheet should exist'
    assert_path_exists File.join(@output_dir, 'groceries.css'), 'groceries CSS should exist'
    assert_path_exists File.join(@output_dir, 'groceries.js'), 'groceries JS should exist'
    assert_path_exists File.join(@output_dir, 'qrcodegen.js'), 'QR code library should exist'
    assert_path_exists File.join(@output_dir, 'manifest.json'), 'PWA manifest should exist'
    assert_path_exists File.join(@output_dir, 'sw.js'), 'service worker should exist'
  end

  def test_recipe_count_matches_source_files
    quick_bites = FamilyRecipes::CONFIG[:quick_bites_filename]
    source_files = Dir.glob(File.join(@recipes_dir, '**', '*')).select do |f|
      File.file?(f) && File.basename(f) != quick_bites
    end

    output_html = Dir.glob(File.join(@output_dir, '*.html')).reject do |f|
      f.end_with?('index.html', '404.html')
    end

    assert_equal source_files.size, output_html.size,
                 'number of recipe HTML files should match number of source files'
  end

  def test_recipe_html_has_expected_structure
    # Spot-check a known recipe
    html_file = File.join(@output_dir, 'hard-boiled-eggs.html')

    assert_path_exists html_file, 'hard-boiled-eggs.html should exist'

    html = File.read(html_file)

    assert_match(/<h1[^>]*>.*Hard-Boiled Eggs/m, html, 'should have title in h1')
    assert_match(/<li.*Water/m, html, 'should list ingredients')
    assert_match(/<h2/, html, 'should have step headers')
  end

  def test_homepage_links_all_recipes
    homepage = File.read(File.join(@output_dir, 'index.html'))

    quick_bites = FamilyRecipes::CONFIG[:quick_bites_filename]
    source_files = Dir.glob(File.join(@recipes_dir, '**', '*')).select do |f|
      File.file?(f) && File.basename(f) != quick_bites
    end

    source_files.each do |f|
      slug = FamilyRecipes.slugify(File.basename(f, '.*'))

      assert_match(/href="#{Regexp.escape(slug)}(\.html)?"/, homepage,
                   "homepage should link to #{slug}")
    end
  end

  def test_ingredient_index_has_entries
    index_html = File.read(File.join(@output_dir, 'index', 'index.html'))
    # Should contain some common ingredient names
    assert_match(/Salt/, index_html, 'index should contain Salt')
    assert_match(/Butter/, index_html, 'index should contain Butter')
  end

  def test_recipe_html_includes_nutrition_facts
    html = File.read(File.join(@output_dir, 'gougeres.html'))

    assert_match(/class="nutrition-facts"/, html, 'recipe with full nutrition data should have nutrition section')
  end

  def test_recipe_html_includes_plural_unit_data_attributes
    html = File.read(File.join(@output_dir, 'gougeres.html'))

    assert_match(/data-quantity-unit-plural/, html,
                 'quantified ingredient should have data-quantity-unit-plural attribute')
  end

  def test_recipe_html_has_cross_reference_links
    html = File.read(File.join(@output_dir, 'white-pizza.html'))

    assert_match(/href="pizza-dough"/, html, 'cross-reference should render as a link to the target recipe')
  end
end
