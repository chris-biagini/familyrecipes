# frozen_string_literal: true

# Test helper - loads the library and sets up test environment

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'minitest/autorun'

module ActionDispatch
  class IntegrationTest
    private

    def create_kitchen_and_user
      @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
      @user = User.create!(name: 'Test User', email: 'test@example.com')
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
