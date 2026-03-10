# frozen_string_literal: true

require 'test_helper'

class IngredientResolverTest < ActiveSupport::TestCase
  FakeEntry = Struct.new(:ingredient_name, :aisle, :aliases, :omit_from_shopping, keyword_init: true) do
    def basis_grams = nil
    def density_grams = nil
  end

  setup do
    @eggs = FakeEntry.new(ingredient_name: 'Eggs', aisle: 'Refrigerated', aliases: [])
    @flour = FakeEntry.new(ingredient_name: 'Flour', aisle: 'Baking', aliases: ['AP flour'])
    @parmesan = FakeEntry.new(ingredient_name: 'Parmesan', aisle: 'Dairy', aliases: ['parmesan cheese'])

    @lookup = {
      'Eggs' => @eggs, 'Egg' => @eggs,
      'Flour' => @flour, 'AP flour' => @flour, 'ap flour' => @flour, 'AP Flour' => @flour,
      'Parmesan' => @parmesan, 'parmesan cheese' => @parmesan, 'Parmesan Cheese' => @parmesan
    }
  end

  test 'resolves exact catalog match' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('Eggs')
  end

  test 'resolves inflector variant to canonical name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('Egg')
  end

  test 'resolves alias to canonical name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Flour', resolver.resolve('AP flour')
  end

  test 'resolves case-insensitive match when exact misses' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('eggs')
    assert_equal 'Eggs', resolver.resolve('EGGS')
    assert_equal 'Flour', resolver.resolve('flour')
  end

  test 'resolves alias case-insensitively' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Parmesan', resolver.resolve('PARMESAN CHEESE')
  end

  test 'returns raw name for uncataloged ingredient' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Seltzer', resolver.resolve('Seltzer')
  end

  test 'collapses uncataloged names case-insensitively to first-seen' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Seltzer', resolver.resolve('Seltzer')
    assert_equal 'Seltzer', resolver.resolve('seltzer')
    assert_equal 'Seltzer', resolver.resolve('SELTZER')
  end

  test 'collapses uncataloged inflector variants to first-seen' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Onion', resolver.resolve('Onion')
    assert_equal 'Onion', resolver.resolve('Onions')
  end

  test 'collapses uncataloged inflector variants when plural seen first' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Onions', resolver.resolve('Onions')
    assert_equal 'Onions', resolver.resolve('Onion')
  end

  test 'never returns nil' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal '', resolver.resolve('')
    assert_equal 'Unknown', resolver.resolve('Unknown')
  end

  test 'catalog_entry returns AR object for cataloged name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal @eggs, resolver.catalog_entry('Eggs')
    assert_equal @eggs, resolver.catalog_entry('Egg')
    assert_equal @eggs, resolver.catalog_entry('eggs')
  end

  test 'catalog_entry returns nil for uncataloged name' do
    resolver = IngredientResolver.new(@lookup)

    assert_nil resolver.catalog_entry('Seltzer')
  end

  test 'cataloged? returns true for known ingredients' do
    resolver = IngredientResolver.new(@lookup)

    assert resolver.cataloged?('Eggs')
    assert resolver.cataloged?('eggs')
    assert resolver.cataloged?('Egg')
  end

  test 'cataloged? returns false for unknown ingredients' do
    resolver = IngredientResolver.new(@lookup)

    assert_not resolver.cataloged?('Seltzer')
  end

  test 'all_keys_for returns all lookup keys mapping to canonical name' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Eggs')

    assert_includes keys, 'Eggs'
    assert_includes keys, 'Egg'
    assert_equal 2, keys.size
  end

  test 'all_keys_for includes the canonical name even if not a lookup key' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Flour')

    assert_includes keys, 'Flour'
    assert_includes keys, 'AP flour'
    assert_includes keys, 'ap flour'
    assert_includes keys, 'AP Flour'
  end

  test 'all_keys_for returns array with just the name for uncataloged ingredients' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Seltzer')

    assert_equal ['Seltzer'], keys
  end

  # --- omit ---

  test 'omitted? returns true for entries with omit_from_shopping' do
    catalog = {
      'Water' => FakeEntry.new(ingredient_name: 'Water', omit_from_shopping: true),
      'Salt' => FakeEntry.new(ingredient_name: 'Salt', omit_from_shopping: false)
    }
    resolver = IngredientResolver.new(catalog)

    assert resolver.omitted?('Water')
    assert_not resolver.omitted?('Salt')
  end

  test 'omitted? returns false for uncataloged ingredients' do
    resolver = IngredientResolver.new({})

    assert_not resolver.omitted?('Unknown')
  end

  test 'omit_set returns downcased names of omitted entries' do
    catalog = {
      'Water' => FakeEntry.new(ingredient_name: 'Water', omit_from_shopping: true),
      'Ice' => FakeEntry.new(ingredient_name: 'Ice', omit_from_shopping: true),
      'Salt' => FakeEntry.new(ingredient_name: 'Salt', omit_from_shopping: false)
    }
    resolver = IngredientResolver.new(catalog)

    assert_equal Set['water', 'ice'], resolver.omit_set
  end

  test 'omit_set is memoized' do
    catalog = {
      'Water' => FakeEntry.new(ingredient_name: 'Water', omit_from_shopping: true)
    }
    resolver = IngredientResolver.new(catalog)

    assert_same resolver.omit_set, resolver.omit_set
  end

  # --- factory ---

  test 'IngredientCatalog.resolver_for returns an IngredientResolver' do
    setup_test_kitchen
    resolver = IngredientCatalog.resolver_for(@kitchen)

    assert_instance_of IngredientResolver, resolver
    assert_kind_of Hash, resolver.lookup
  end
end
