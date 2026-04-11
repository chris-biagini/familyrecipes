# frozen_string_literal: true

require 'test_helper'

class AuthTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia


      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD
  end

  test 'unauthenticated POST to recipes returns 403' do
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: "# New\n\n## Step (do)\n\n- Flour\n\nMix." },
         as: :json

    assert_response :forbidden
  end

  test 'unauthenticated PATCH to recipes returns 403' do
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: "# Focaccia\n\n## Step (do)\n\n- Flour\n\nMix." },
          as: :json

    assert_response :forbidden
  end

  test 'unauthenticated DELETE to recipes returns 403' do
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'unauthenticated PATCH to quick_bites returns 403' do
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '## Snacks' },
          as: :json

    assert_response :forbidden
  end

  test 'non-member cannot write to a kitchen' do
    outsider_kitchen = Kitchen.create!(name: 'Other Kitchen', slug: 'other-kitchen')
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')
    ActsAsTenant.with_tenant(outsider_kitchen) do
      Membership.create!(kitchen: outsider_kitchen, user: outsider)
    end
    get dev_login_path(id: outsider.id)

    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: "# New\n\n## Step (do)\n\n- Flour\n\nMix." },
         as: :json

    assert_response :forbidden
  end

  test 'recipe page hides edit button for non-members' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-button', count: 0
  end

  test 'recipe page shows edit button for members' do
    log_in

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-button', count: 1
  end

  test 'homepage hides new button for non-members' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#new-recipe-button', count: 0
  end

  test 'homepage shows new button for members' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#new-recipe-button', count: 1
  end

  test 'groceries page requires membership' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'groceries page shows edit buttons for members' do
    log_in

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-aisle-order-button', count: 1
  end

  test 'trusted-header environment variables are ignored' do
    get root_path, env: {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_REMOTE_USER' => 'alice',
      'HTTP_REMOTE_EMAIL' => 'alice@example.com',
      'HTTP_REMOTE_NAME' => 'Alice'
    }

    assert_nil cookies[:session_id].presence
  end
end
