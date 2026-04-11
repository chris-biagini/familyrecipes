# frozen_string_literal: true

if ENV['COVERAGE'] || ENV['RELEASE_AUDIT']
  require 'simplecov'
  SimpleCov.start 'rails' do
    enable_coverage :branch
    minimum_coverage line: 0 # Floor enforced by release audit task, not SimpleCov
    add_filter '/test/'
    add_filter '/db/'
    add_filter '/config/'
    add_filter '/vendor/'
  end
end

# Two test hierarchies coexist in this project:
#
# 1. Rails tests (test/controllers/, test/models/, test/services/, test/integration/,
#    test/channels/, test/helpers/, test/jobs/, test/lib/) inherit
#    ActiveSupport::TestCase and have access to assert_not_*, assert_difference, etc.
#
# 2. Top-level parser unit tests (test/recipe_test.rb, test/nutrition_calculator_test.rb,
#    etc.) inherit Minitest::Test directly and do NOT have ActiveSupport extensions.
#    RuboCop's Rails/RefuteMethods cop is excluded for these files.
#
# ActiveSupport::TestCase helpers: setup_test_kitchen, setup_test_category,
#   create_catalog_entry, create_kitchen_and_user.
# ActionDispatch::IntegrationTest helpers: log_in, kitchen_slug.

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'action_cable/test_helper'
require 'action_cable/channel/test_case'
require 'minitest/autorun'

# Bullet integration: start/end tracking around each test so N+1 queries
# introduced by new code are caught automatically.
if defined?(Bullet)
  module ActiveSupport
    class TestCase
      setup { Bullet.start_request }
      teardown { Bullet.end_request }
    end
  end
end

# Clear the cache before each test. Rails 8's `rate_limit` is backed by
# Rails.cache, so shared state across tests would otherwise leak counters
# between controller tests that exercise rate-limited actions.
module ActiveSupport
  class TestCase
    setup { Rails.cache.clear }
  end
end

module ActiveSupport
  class TestCase
    private

    def setup_test_kitchen
      @kitchen = Kitchen.first || Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
      defaults = Kitchen.column_defaults.slice('aisle_order', 'site_title', 'show_nutrition', 'decorate_tags')
      @kitchen.update_columns(defaults) # rubocop:disable Rails/SkipsModelValidations
      ActsAsTenant.current_tenant = @kitchen
      cleanup_meal_plan_tables
    end

    def cleanup_meal_plan_tables
      MealPlanSelection.where(kitchen_id: @kitchen.id).delete_all
      OnHandEntry.where(kitchen_id: @kitchen.id).delete_all
      CustomGroceryItem.where(kitchen_id: @kitchen.id).delete_all
      CookHistoryEntry.where(kitchen_id: @kitchen.id).delete_all
    end

    def setup_test_category(name: 'Test', slug: nil)
      slug ||= FamilyRecipes.slugify(name)
      @category = Category.find_or_create_by!(name:, slug:)
    end

    def create_catalog_entry(name, aisle: nil, basis_grams: nil, **nutrient_attrs)
      IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: name) do |e|
        e.aisle = aisle
        e.basis_grams = basis_grams
        nutrient_attrs.each { |attr, val| e.public_send(:"#{attr}=", val) }
      end
    end

    def create_kitchen_and_user
      setup_test_kitchen
      @user = User.create!(name: 'Test User', email: 'test@example.com')
      Membership.create!(kitchen: @kitchen, user: @user)
    end

    def create_recipe(markdown, category_name: 'Miscellaneous', kitchen: @kitchen)
      RecipeWriteService.create(markdown:, kitchen:, category_name:).recipe
    end

    def create_quick_bite(title, category_name: 'Snacks', ingredients: [title])
      cat = Category.find_or_create_for(@kitchen, category_name)
      qb = QuickBite.create!(title:, category: cat, position: QuickBite.where(kitchen_id: @kitchen.id).count)
      ingredients.each_with_index do |name, idx|
        qb.quick_bite_ingredients.create!(name:, position: idx)
      end
      qb
    end
  end
end

module ActionDispatch
  class IntegrationTest
    private

    def log_in
      get dev_login_path(id: @user.id)
    end

    def kitchen_slug
      @kitchen.slug
    end
  end
end
