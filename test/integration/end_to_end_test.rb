# frozen_string_literal: true

require 'test_helper'

class EndToEndTest < ActionDispatch::IntegrationTest
  setup do
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0)
    @pizza = Category.create!(name: 'Pizza', slug: 'pizza', position: 1)

    MarkdownImporter.import(<<~MD)
      # Pizza Dough

      A versatile dough for any pizza.

      Category: Pizza
      Makes: 4 dough balls

      ## Mix the dough (combine dry and wet)

      - Flour, 3 cups
      - Water, 1 cup: Warm.
      - Yeast, 1 tsp
      - Salt, 1 tsp
      - Olive oil, 2 tbsp

      Mix everything together for 10* minutes.

      ## Let it rise (bulk ferment)

      Let the dough rise for 2* hours at room temperature.

      ---

      Adapted from a classic Neapolitan recipe.
    MD

    MarkdownImporter.import(<<~MD)
      # White Pizza

      A simple pizza bianca.

      Category: Pizza
      Serves: 4

      ## Assemble (top the dough)

      - @[Pizza Dough]
      - Mozzarella, 8 oz: Sliced.
      - Ricotta, 4 oz

      Top the dough and bake at 500* degrees for 12* minutes.
    MD

    MarkdownImporter.import(<<~MD)
      # Focaccia

      Just a little sweet.

      Category: Bread
      Serves: 8

      ## Make dough (mix ingredients)

      - Flour, 4 cups
      - Water, 1.5 cups: Warm.
      - Honey, 1 tbsp
      - Salt, 2 tsp

      Combine and let rest for 1* hour.
    MD
  end

  # -- Layout --

  test 'layout includes nav with all three links' do
    get root_path

    assert_select 'nav a.home', 'Home'
    assert_select 'nav a.index', 'Index'
    assert_select 'nav a.groceries', 'Groceries'
  end

  test 'layout includes meta tags and stylesheet' do
    get root_path

    assert_select 'meta[charset="UTF-8"]'
    assert_select 'meta[name="viewport"]'
    assert_select 'meta[name="theme-color"]'
    assert_select 'link[rel="stylesheet"]'
    assert_select 'link[rel="icon"]'
  end

  # -- Homepage --

  test 'homepage renders site title and subtitle from config' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Our Recipes'
    assert_select 'header p'
  end

  test 'homepage renders footer with GitHub link' do
    get root_path

    assert_select 'footer a[href*="github"]'
  end

  test 'homepage renders categories as sections with anchors' do
    get root_path

    assert_select 'section#bread h2', 'Bread'
    assert_select 'section#pizza h2', 'Pizza'
    assert_select '.toc_nav a[href="#bread"]', 'Bread'
    assert_select '.toc_nav a[href="#pizza"]', 'Pizza'
  end

  # -- Recipe --

  test 'recipe page renders description' do
    get recipe_path('focaccia')

    assert_response :success
    assert_select 'header p', 'Just a little sweet.'
  end

  test 'recipe page renders footer content' do
    get recipe_path('pizza-dough')

    assert_response :success
    assert_select 'footer', /Adapted from a classic Neapolitan recipe/
  end

  test 'recipe page renders Makes metadata' do
    get recipe_path('pizza-dough')

    assert_select '.recipe-meta', /Makes/
    assert_select '.recipe-meta', /dough balls/
  end

  test 'recipe page renders Serves metadata' do
    get recipe_path('focaccia')

    assert_select '.recipe-meta', /Serves/
  end

  test 'recipe page renders category link in metadata' do
    get recipe_path('focaccia')

    assert_select '.recipe-meta a[href*="#bread"]', 'Bread'
  end

  test 'recipe page renders scalable numbers in instructions' do
    get recipe_path('pizza-dough')

    assert_select '.instructions .scalable'
  end

  test 'recipe page renders ingredient prep notes' do
    get recipe_path('pizza-dough')

    assert_select '.ingredients small', 'Warm.'
  end

  test 'recipe page renders cross-reference as link' do
    get recipe_path('white-pizza')

    assert_response :success
    assert_select 'li.cross-reference a[href=?]', recipe_path('pizza-dough'), text: 'Pizza Dough'
  end

  test 'recipe page includes body data attributes for state manager' do
    get recipe_path('focaccia')

    assert_match(/data-recipe-id="focaccia"/, response.body)
    assert_match(/data-version-hash=/, response.body)
  end

  test 'recipe page renders step-only sections without ingredients' do
    get recipe_path('pizza-dough')

    assert_select 'h2', text: /rise/i
  end

  # -- Ingredients Index --

  test 'ingredients index lists all ingredients from all recipes' do
    get ingredients_path

    assert_response :success
    assert_select 'h2', 'Mozzarella'
    assert_select 'h2', 'Honey'
  end

  test 'ingredients index links back to recipe pages' do
    get ingredients_path

    assert_select 'a[href=?]', recipe_path('pizza-dough')
    assert_select 'a[href=?]', recipe_path('focaccia')
  end

  # -- Groceries --

  test 'groceries page renders recipe checkboxes grouped by category' do
    get groceries_path

    assert_response :success
    assert_select '#recipe-selector .category h2', 'Bread'
    assert_select '#recipe-selector .category h2', 'Pizza'
    assert_select 'input[type=checkbox][data-title="Focaccia"]'
    assert_select 'input[type=checkbox][data-title="Pizza Dough"]'
  end

  test 'groceries page recipe checkboxes contain ingredient JSON' do
    get groceries_path

    checkbox = css_select('input[data-title="Focaccia"]').first

    assert_predicate checkbox, :present?
    ingredients = JSON.parse(checkbox['data-ingredients'])

    assert(ingredients.any? { |name, _| name.include?('Flour') })
  end

  test 'groceries page renders aisle details elements' do
    get groceries_path

    assert_select 'details.aisle'
    assert_select '#misc-aisle'
  end

  test 'groceries page includes noscript fallback' do
    get groceries_path

    assert_select 'noscript', /JavaScript/
  end

  # -- Navigation between pages --

  test 'clicking a recipe from homepage leads to valid recipe page' do
    get root_path

    recipe_link = css_select('a[href*="/recipes/focaccia"]').first

    assert_predicate recipe_link, :present?

    get recipe_link['href']

    assert_response :success
    assert_select 'h1', 'Focaccia'
  end

  test 'recipe page links back to homepage category anchor' do
    get recipe_path('focaccia')

    assert_select '.recipe-meta a[href=?]', root_path(anchor: 'bread')
  end
end
