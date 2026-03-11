# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'requires membership to view settings' do
    get settings_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'renders settings page for logged-in member' do
    log_in
    get settings_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Settings'
  end

  test 'requires membership to update settings' do
    patch settings_path(kitchen_slug: kitchen_slug), params: { kitchen: { site_title: 'New' } }

    assert_response :forbidden
  end

  test 'updates site settings' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { site_title: 'New Title', homepage_heading: 'New Heading', homepage_subtitle: 'New Sub' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    follow_redirect!
    @kitchen.reload

    assert_equal 'New Title', @kitchen.site_title
    assert_equal 'New Heading', @kitchen.homepage_heading
    assert_equal 'New Sub', @kitchen.homepage_subtitle
  end

  test 'updates usda api key' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { usda_api_key: 'my-secret-key' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    @kitchen.reload

    assert_equal 'my-secret-key', @kitchen.usda_api_key
  end

  test 'gear icon visible in navbar for members' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav a.nav-settings-link'
  end

  test 'gear icon hidden when not logged in' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav a.nav-settings-link', count: 0
  end

  test 'rejects unpermitted params' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug), params: {
      kitchen: { site_title: 'OK', slug: 'hacked' }
    }

    assert_redirected_to settings_path(kitchen_slug: kitchen_slug)
    @kitchen.reload

    assert_equal 'OK', @kitchen.site_title
    assert_equal 'test-kitchen', @kitchen.slug
  end
end
