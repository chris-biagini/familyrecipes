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
# Helpers below: create_kitchen_and_user (sets @kitchen, @user, tenant),
# log_in (logs in @user via dev login), kitchen_slug (returns @kitchen.slug).

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'action_cable/test_helper'
require 'action_cable/channel/test_case'
require 'minitest/autorun'

module ActionDispatch
  class IntegrationTest
    private

    def create_kitchen_and_user
      @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
      @user = User.create!(name: 'Test User', email: 'test@example.com')
      ActsAsTenant.current_tenant = @kitchen
      Membership.create!(kitchen: @kitchen, user: @user)
    end

    def log_in
      get dev_login_path(id: @user.id)
    end

    def kitchen_slug
      @kitchen.slug
    end
  end
end
