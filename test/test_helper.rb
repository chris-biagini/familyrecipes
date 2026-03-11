# frozen_string_literal: true

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

module ActiveSupport
  class TestCase
    private

    def setup_test_kitchen
      ActsAsTenant.without_tenant do
        Kitchen.where.not(slug: 'test-kitchen').destroy_all
      end
      @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
      ActsAsTenant.current_tenant = @kitchen
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

    def with_multi_kitchen
      original = ENV.fetch('MULTI_KITCHEN', nil)
      ENV['MULTI_KITCHEN'] = 'true'
      yield
    ensure
      ENV['MULTI_KITCHEN'] = original
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
