# frozen_string_literal: true

require 'test_helper'

# Verifies acts_as_tenant prevents cross-kitchen access on write-path
# controllers. Each test logs in as Kitchen B's user and attempts to
# access Kitchen A's resources — expecting 403 since the membership
# check fails for a user who is not a member of the target kitchen.
class TenantIsolationTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user

    @kitchen_b = Kitchen.create!(name: 'Other Kitchen', slug: 'other-kitchen')
    @user_b = User.create!(name: 'Other User', email: 'other@example.com')
    ActsAsTenant.with_tenant(@kitchen_b) do
      Membership.create!(kitchen: @kitchen_b, user: @user_b)
    end

    @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    markdown = "# Focaccia\n\n## Mix (combine)\n\n- Flour, 3 cups\n\nMix."
    MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
  end

  # --- RecipesController ---

  test 'kitchen B user cannot update kitchen A recipe' do
    log_in_as_user_b

    patch recipe_path('focaccia', kitchen_slug: @kitchen.slug),
          params: { markdown_source: "# Hacked\n\n## Step (do it)\n\n- Evil, 1 cup\n\nEvil." },
          as: :json

    assert_response :forbidden
  end

  test 'kitchen B user cannot destroy kitchen A recipe' do
    log_in_as_user_b

    delete recipe_path('focaccia', kitchen_slug: @kitchen.slug), as: :json

    assert_response :forbidden
  end

  # --- SettingsController ---

  test 'kitchen B user cannot update kitchen A settings' do
    log_in_as_user_b

    patch settings_path(kitchen_slug: @kitchen.slug),
          params: { kitchen: { site_title: 'Hacked Title' } },
          as: :json

    assert_response :forbidden
  end

  # --- ExportsController ---

  test 'kitchen B user cannot export kitchen A data' do
    log_in_as_user_b

    get export_path(kitchen_slug: @kitchen.slug)

    assert_response :forbidden
  end

  # --- NutritionEntriesController ---

  test 'kitchen B user cannot upsert nutrition entry in kitchen A' do
    log_in_as_user_b

    post nutrition_entry_upsert_path('flour', kitchen_slug: @kitchen.slug),
         params: { nutrients: { basis_grams: 30, calories: 110 }, density: nil, portions: {}, aisle: nil },
         as: :json

    assert_response :forbidden
  end

  private

  def log_in_as_user_b
    get dev_login_path(id: @user_b.id)
  end
end
