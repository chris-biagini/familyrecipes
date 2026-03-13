# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'requires membership to view settings' do
    get settings_path(kitchen_slug: kitchen_slug), as: :json
    assert_response :forbidden
  end

  test 'returns settings as JSON for logged-in member' do
    log_in
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    data = response.parsed_body
    assert_equal @kitchen.site_title, data['site_title']
    assert_equal @kitchen.homepage_heading, data['homepage_heading']
    assert_equal @kitchen.homepage_subtitle, data['homepage_subtitle']
    assert data.key?('usda_api_key')
  end

  test 'requires membership to update settings' do
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'New' } }, as: :json
    assert_response :forbidden
  end

  test 'updates site settings via JSON' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'New Title', homepage_heading: 'New Heading', homepage_subtitle: 'New Sub' } },
          as: :json

    assert_response :success
    @kitchen.reload
    assert_equal 'New Title', @kitchen.site_title
    assert_equal 'New Heading', @kitchen.homepage_heading
    assert_equal 'New Sub', @kitchen.homepage_subtitle
  end

  test 'updates usda api key via JSON' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { usda_api_key: 'my-secret-key' } }, as: :json

    assert_response :success
    @kitchen.reload
    assert_equal 'my-secret-key', @kitchen.usda_api_key
  end

  # NOTE: These two nav tests assert `button.nav-settings-link` which requires
  # the nav partial update from Task 3. Skipped until then.
  test 'gear button visible in navbar for members' do
    skip 'Needs nav partial update (Task 3) to change <a> to <button>'
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_select 'nav button.nav-settings-link'
  end

  test 'gear button hidden when not logged in' do
    skip 'Needs nav partial update (Task 3) to change <a> to <button>'
    get kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_select 'nav button.nav-settings-link', count: 0
  end

  test 'rejects unpermitted params' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'OK', slug: 'hacked' } }, as: :json

    assert_response :success
    @kitchen.reload
    assert_equal 'OK', @kitchen.site_title
    assert_equal 'test-kitchen', @kitchen.slug
  end
end
