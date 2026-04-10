# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class KitchenTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen_id: nil).delete_all
  end

  test 'requires name' do
    kitchen = Kitchen.new(slug: 'test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:name], "can't be blank"
  end

  test 'requires slug' do
    kitchen = Kitchen.new(name: 'Test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:slug], "can't be blank"
  end

  test 'enforces unique slug' do
    dup = Kitchen.new(name: 'Second', slug: @kitchen.slug)

    assert_not dup.valid?
    assert_includes dup.errors[:slug], 'has already been taken'
  end

  test 'duplicate slug error reads as Kitchen name' do
    with_multi_kitchen do
      Kitchen.create!(name: 'Shared Kitchen', slug: 'shared-kitchen')
      dup = Kitchen.new(name: 'Shared Kitchen', slug: 'shared-kitchen')

      assert_not dup.valid?
      assert_includes dup.errors.full_messages, 'Kitchen name has already been taken'
    end
  end

  test 'member? returns true for kitchen members' do
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    Membership.create!(kitchen: @kitchen, user: user)

    assert @kitchen.member?(user)
  end

  test 'member? returns false for non-members' do
    user = User.create!(name: 'Alice', email: 'alice@example.com')

    assert_not @kitchen.member?(user)
  end

  test 'member? returns false for nil user' do
    assert_not @kitchen.member?(nil)
  end

  test 'all_aisles returns empty array when no aisles exist' do
    assert_empty @kitchen.all_aisles
  end

  test 'all_aisles returns aisle_order entries' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    assert_equal %w[Produce Baking], @kitchen.all_aisles
  end

  test 'all_aisles merges catalog aisles not in order' do
    @kitchen.update!(aisle_order: 'Produce')
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Cumin', aisle: 'Spices', basis_grams: 6)

    aisles = @kitchen.all_aisles

    assert_equal 'Produce', aisles.first
    assert_includes aisles, 'Baking'
    assert_includes aisles, 'Spices'
  end

  test 'all_aisles excludes entries with nil aisle' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Bay leaves', aisle: nil, omit_from_shopping: true,
                              basis_grams: 1)

    assert_empty @kitchen.all_aisles
  end

  test 'normalize_aisle_order! collapses case variants keeping first casing' do
    @kitchen.update!(aisle_order: "Produce\nproduce\nPRODUCE\nBaking")
    @kitchen.normalize_aisle_order!

    assert_equal "Produce\nBaking", @kitchen.aisle_order
  end

  test 'all_aisles deduplicates case variants across sources' do
    @kitchen.update!(aisle_order: 'baking')
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)

    assert_equal ['baking'], @kitchen.all_aisles
  end

  test 'all_aisles deduplicates across sources' do
    @kitchen.update!(aisle_order: 'Baking')
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)

    assert_equal ['Baking'], @kitchen.all_aisles
  end

  test 'broadcast_update sends refresh to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      @kitchen.broadcast_update
    end
  end

  test 'allows multiple kitchens to coexist' do
    second = Kitchen.new(name: 'Second', slug: 'second')

    assert_predicate second, :valid?
  end

  test 'encrypts usda_api_key at rest' do
    setup_test_kitchen
    @kitchen.update!(usda_api_key: 'test-api-key-123')
    @kitchen.reload

    assert_equal 'test-api-key-123', @kitchen.usda_api_key

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT usda_api_key FROM kitchens WHERE id = #{@kitchen.id}"
    )

    assert_not_equal 'test-api-key-123', raw
  end

  test 'encrypts anthropic_api_key at rest' do
    ActsAsTenant.without_tenant do
      @kitchen.update!(anthropic_api_key: 'sk-ant-test-key-123')
    end

    assert_equal 'sk-ant-test-key-123', @kitchen.anthropic_api_key

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT anthropic_api_key FROM kitchens WHERE id = #{@kitchen.id}"
    )

    assert_not_equal 'sk-ant-test-key-123', raw
  end

  test 'all_aisles prefers kitchen catalog entries over global' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', aisle: 'Pantry', basis_grams: 30)

    aisles = @kitchen.all_aisles

    assert_includes aisles, 'Pantry'
    assert_not_includes aisles, 'Baking'
  end
end
