# frozen_string_literal: true

require 'test_helper'

class KitchensControllerTest < ActionDispatch::IntegrationTest
  test 'new renders creation form' do
    with_multi_kitchen do
      get new_kitchen_path

      assert_response :success
      assert_select 'form'
    end
  end

  test 'create builds kitchen, user, membership, meal plan, and session' do
    with_multi_kitchen do
      assert_difference -> { Kitchen.count }, 1 do
        assert_difference -> { User.count }, 1 do
          assert_difference -> { ActsAsTenant.without_tenant { MealPlan.count } }, 1 do
            post new_kitchen_path, params: {
              name: 'Chef User',
              email: 'chef@example.com',
              kitchen_name: 'Our Kitchen'
            }
          end
        end
      end

      kitchen = Kitchen.find_by(slug: 'our-kitchen')

      assert_predicate kitchen, :present?
      assert_predicate kitchen.join_code, :present?

      user = User.find_by(email: 'chef@example.com')

      assert_equal 'Chef User', user.name

      ActsAsTenant.with_tenant(kitchen) do
        assert kitchen.member?(user)

        membership = kitchen.memberships.find_by(user: user)

        assert_equal 'owner', membership.role
      end

      assert_redirected_to kitchen_root_path(kitchen_slug: 'our-kitchen')
      assert_predicate cookies[:session_id], :present?
    end
  end

  test 'create with existing user email reuses user' do
    User.create!(name: 'Existing', email: 'existing@example.com')

    with_multi_kitchen do
      assert_no_difference 'User.count' do
        assert_difference 'Kitchen.count', 1 do
          post new_kitchen_path, params: {
            name: 'Existing',
            email: 'existing@example.com',
            kitchen_name: 'Second Kitchen'
          }
        end
      end
    end
  end

  test 'create with validation errors re-renders form' do
    with_multi_kitchen do
      post new_kitchen_path, params: {
        name: '',
        email: 'bad',
        kitchen_name: ''
      }

      assert_response :unprocessable_content
      assert_select 'form'
    end
  end

  test 'create redirects to home if already logged in and not intentional' do
    create_kitchen_and_user
    log_in

    get new_kitchen_path

    assert_redirected_to root_path
  end

  test 'create allows logged-in user when intentional param present' do
    create_kitchen_and_user
    log_in

    with_multi_kitchen do
      get new_kitchen_path(intentional: true)

      assert_response :success
    end
  end
end
