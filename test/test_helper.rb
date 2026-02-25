# frozen_string_literal: true

# Test helper - loads the library and sets up test environment

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

    def add_placeholder_auth_routes
      return if Rails.application.routes.named_routes.key?(:login)

      @routes_need_reload = true
      Rails.application.routes.append do
        get 'login', to: 'dev_sessions#create', as: :login
        delete 'logout', to: 'dev_sessions#destroy', as: :logout
      end
    end

    def reload_original_routes
      return unless @routes_need_reload

      Rails.application.reload_routes!
    end
  end
end
