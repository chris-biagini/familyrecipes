# frozen_string_literal: true

require 'test_helper'

class JoinsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'new renders join code form' do
    get join_kitchen_path

    assert_response :success
    assert_select 'form'
  end

  test 'verify with invalid code shows error' do
    post verify_join_path, params: { join_code: 'invalid code here now' }

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'verify with valid code renders email form' do
    post verify_join_path, params: { join_code: @kitchen.join_code }

    assert_response :success
    assert_select 'input[name="email"]'
  end

  test 'complete with known email re-authenticates' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_no_difference ['User.count'] do
      post complete_join_path, params: {
        email: @user.email,
        signed_kitchen_id: signed_kitchen
      }
    end

    assert_response :redirect
    assert_match %r{/welcome\?k=}, response.location
    assert_predicate cookies[:session_id], :present?
  end

  test 'complete with unknown email renders name form' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    post complete_join_path, params: {
      email: 'newperson@example.com',
      signed_kitchen_id: signed_kitchen
    }

    assert_response :success
    assert_select 'input[name="name"]'
  end

  test 'complete with name creates user and membership' do
    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_difference 'User.count', 1 do
      post complete_join_path, params: {
        email: 'newperson@example.com',
        name: 'New Person',
        signed_kitchen_id: signed_kitchen
      }
    end

    assert_response :redirect
    assert_match %r{/welcome\?k=}, response.location

    user = User.find_by(email: 'newperson@example.com')

    assert_equal 'New Person', user.name
    assert ActsAsTenant.with_tenant(@kitchen) { @kitchen.member?(user) }
  end

  test 'complete with existing user from another kitchen creates membership only' do
    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')
    ActsAsTenant.with_tenant(other_kitchen) do
      Membership.create!(kitchen: other_kitchen, user: outsider)
    end

    signed_kitchen = sign_kitchen_id(@kitchen.id)

    assert_no_difference 'User.count' do
      post complete_join_path, params: {
        email: 'outsider@example.com',
        signed_kitchen_id: signed_kitchen
      }
    end

    assert_response :redirect
    assert_match %r{/welcome\?k=}, response.location
    assert ActsAsTenant.with_tenant(@kitchen) { @kitchen.member?(outsider) }
  end

  test 'complete with tampered signed kitchen ID is rejected' do
    post complete_join_path, params: {
      email: @user.email,
      signed_kitchen_id: 'tampered-value'
    }

    assert_redirected_to join_kitchen_path
  end

  private

  def sign_kitchen_id(id)
    Rails.application.message_verifier(:join).generate(id, purpose: :join, expires_in: 15.minutes)
  end
end
