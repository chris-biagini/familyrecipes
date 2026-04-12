# frozen_string_literal: true

require 'test_helper'

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    IngredientCatalog.where(kitchen_id: nil).delete_all
  end

  teardown do
    ENV.delete('USDA_API_KEY')
  end

  test 'requires membership to view ingredients' do
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'renders ingredient index grouped by ingredient name' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Ingredients'
    assert_select 'tr.ingredient-row[data-ingredient-name="Flour"]'
  end

  test 'groups multiple recipes under the same ingredient' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pizza Dough


      ## Mix (combine)

      - Flour, 4 cups

      Knead well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-ingredient-name="Flour"]'
  end

  test 'sorts ingredients alphabetically' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Yeast, 1 tsp
      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    names = css_select('tr.ingredient-row').map { |tr| tr['data-ingredient-name'] } # rubocop:disable Rails/Pluck

    assert_equal names, names.sort_by(&:downcase)
  end

  test 'does not duplicate a recipe under the same ingredient' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Step One (mix)

      - Flour, 2 cups

      Mix.

      ## Step Two (more flour)

      - Flour, 1 cup

      Add more flour.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-ingredient-name="Flour"]'
  end

  test 'shows missing nutrition badge for ingredients without data' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-has-nutrition="false"]'
  end

  test 'shows global badge for ingredients with global nutrition data' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-has-nutrition="true"]'
  end

  test 'shows custom badge for ingredients with kitchen override' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-has-nutrition="true"]'
  end

  test 'consolidates singular and plural ingredient variants into one entry' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Topping (add)

      - Onion, 1: thinly sliced

      Scatter over dough.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Pizza Dough


      ## Topping (add)

      - Onions, 2: diced

      Scatter over dough.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    rows = css_select('tr.ingredient-row').select { |tr| tr['data-ingredient-name'].include?('Onion') }

    assert_equal 1, rows.size, 'Expected singular and plural Onion to merge into one row'
  end

  test 'uses catalog entry name as canonical form for variants' do
    IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Brioche


      ## Mix (combine)

      - Egg, 1

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-ingredient-name="Eggs"]'
  end

  test 'shows missing ingredients banner when nutrition data is absent' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#ingredients-summary'
  end

  # --- edit action (Turbo Frame editor form) ---

  test 'edit returns structured form for ingredient with data' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110,
                              fat: 0.5, saturated_fat: 0, trans_fat: 0, cholesterol: 0, sodium: 5,
                              carbs: 23, fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3,
                              density_grams: 120, density_volume: 1, density_unit: 'cup')

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'edit returns blank form for ingredient without data' do
    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
  end

  test 'edit includes recipe links for ingredient' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'a', text: 'Focaccia'
  end

  test 'edit finds recipes via inflected variant names' do
    IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Brioche


      ## Mix (combine)

      - Egg, 1

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Eggs', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'a', text: 'Brioche'
  end

  test 'edit finds recipes via catalog alias names' do
    IngredientCatalog.create!(ingredient_name: 'Flour (all-purpose)',
                              basis_grams: 30, calories: 110,
                              aliases: ['AP flour', 'All-purpose flour'])
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - All-purpose flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Flour (all-purpose)', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'a', text: 'Focaccia'
  end

  test 'edit does not duplicate recipes using ingredient in multiple steps' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Step One (mix)

      - Flour, 2 cups

      Mix.

      ## Step Two (more flour)

      - Flour, 1 cup

      Add more flour.
    MD

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'a', text: 'Focaccia', count: 1
  end

  test 'edit displays existing aliases in editor form' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30, aliases: ['AP flour', 'Plain flour']
    )
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Test


      ## Mix (combine)

      - Flour (all-purpose), 2 cups

      Mix.
    MD

    log_in
    get ingredient_edit_path('Flour (all-purpose)', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.alias-chip-text', text: 'AP flour'
    assert_select '.alias-chip-text', text: 'Plain flour'
  end

  test 'index renders not_resolvable filter pill with coverage count' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'button.btn-pill[data-filter="not_resolvable"]'
  end

  test 'edit renders USDA search panel when API key is set' do
    ENV['USDA_API_KEY'] = 'test-key'
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
    MD

    log_in
    get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
        headers: { 'Accept' => 'text/html' }

    assert_response :success
    assert_select 'div[data-nutrition-editor-target="usdaPanel"]'
    assert_select 'input[data-nutrition-editor-target="usdaQuery"]'
  end

  test 'edit hides USDA search panel when no API key' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
    MD

    log_in
    get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
        headers: { 'Accept' => 'text/html' }

    assert_response :success
    assert_select 'div[data-nutrition-editor-target="usdaPanel"]', count: 0
  end

  test 'edit form starts with all sections collapsed and density candidates hidden' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
    MD

    log_in
    get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
        headers: { 'Accept' => 'text/html' }

    assert_response :success
    assert_select 'details.collapse-header:not([open])', minimum: 1
    assert_select 'details.editor-density-candidates[hidden]'
  end

  test 'rows have data-source attribute' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-source="custom"]'
  end

  test 'renders custom filter pill' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'button.btn-pill[data-filter="custom"]'
  end

  test 'renders inline ingredient icons for custom entry' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 100,
                              calories: 364, density_grams: 120, density_volume: 1,
                              density_unit: 'cup')
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'td.col-name .ingredient-icons svg.ingredient-icon' do |icons|
      assert_equal 1, icons.size
      assert_equal 'Custom entry', icons.first['aria-label']
    end
  end

  test 'does not render Data column header' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'th.col-data', count: 0
  end

  test 'collapsed summary shows check icon when all recipe units are resolvable' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110,
      density_grams: 120, density_volume: 1, density_unit: 'cup'
    )
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'summary .editor-summary-meta svg path[d="M4 12l6 6L20 6"]'
  end

  test 'collapsed summary shows x icon when some recipe units are unresolvable' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110
    )
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'summary .editor-summary-meta svg line[x1="6"][y1="6"]'
  end

  test 'index does not render no_density filter pill' do
    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_no_match 'No Density', response.body
    assert_select 'button.btn-pill[data-filter="no_density"]', count: 0
  end

  test 'index does not render apple or scale icons in ingredient rows' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 100,
                              calories: 364, density_grams: 120, density_volume: 1, density_unit: 'cup')
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'svg.ingredient-icon' do |icons|
      icon_labels = icons.pluck('aria-label')

      assert_not_includes icon_labels, 'Has nutrition'
      assert_not_includes icon_labels, 'Has density'
    end
  end

  test 'index renders data-qb-only attribute on ingredient rows' do
    create_quick_bite('Toast', ingredients: ['butter'])
    log_in
    get ingredients_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'tr.ingredient-row[data-qb-only="true"]'
  end

  test 'edit hides nutrition section for qb_only ingredient' do
    create_quick_bite('Toast', ingredients: ['butter'])
    log_in
    get ingredient_edit_path('butter', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details[data-section-key="nutrition"]', count: 0
  end

  test 'edit hides conversions section for qb_only ingredient' do
    create_quick_bite('Toast', ingredients: ['butter'])
    log_in
    get ingredient_edit_path('butter', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details[data-section-key="conversions"]', count: 0
  end

  test 'edit shows nutrition and conversions for recipe ingredient' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'details[data-section-key="nutrition"]', count: 1
    assert_select 'details[data-section-key="conversions"]', count: 1
  end

  test 'edit requires membership' do
    get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'edit renders error partial when action raises' do
    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups
    MD

    log_in
    IngredientCatalog.stub(:resolver_for, ->(_) { raise 'test explosion' }) do
      get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
          headers: { 'Accept' => 'text/html' }
    end

    assert_response :success
    assert_select 'turbo-frame#nutrition-editor-form'
    assert_select '.editor-error-message', /test explosion/
  end
end
