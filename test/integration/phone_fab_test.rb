# frozen_string_literal: true

require 'test_helper'

class PhoneFabTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'phone FAB renders on homepage' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.phone-fab' do
      assert_select '.fab-button[aria-label="Menu"]'
      assert_select '.fab-panel[role="dialog"]'
      assert_select '.fab-overlay'
    end
  end

  test 'phone FAB panel contains nav links matching top nav' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-nav-links' do
      assert_select 'a.recipes'
      assert_select 'a.ingredients'
      assert_select 'a.menu'
      assert_select 'a.groceries'
    end
  end

  test 'phone FAB panel contains icon buttons' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-icon-buttons' do
      assert_select 'button[aria-label="Search recipes"]'
      assert_select 'button[aria-label="Settings"]'
    end
  end

  test 'phone FAB button starts closed' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-button[aria-expanded="false"]'
    assert_select '.fab-panel[hidden]'
    assert_select '.fab-overlay[hidden]'
  end

  test 'top nav still renders alongside FAB' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav[data-controller="nav-menu"]'
    assert_select '.phone-fab'
  end

  test 'phone FAB renders on recipe page' do
    recipe = ActsAsTenant.with_tenant(@kitchen) do
      Category.create!(name: 'Mains', kitchen: @kitchen)
              .recipes.create!(title: 'Test Recipe', kitchen: @kitchen)
    end

    get recipe_path(recipe.slug, kitchen_slug: kitchen_slug)

    assert_select '.phone-fab .fab-button'
  end

  test 'phone FAB omits settings button when logged out' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select '.fab-icon-buttons button[aria-label="Settings"]', count: 0
  end
end
