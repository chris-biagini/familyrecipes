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

  test 'POST /join/complete with known email creates a :join magic link and delivers mail' do
    kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
    signed = sign_kitchen_id(kitchen_being_joined.id)
    joiner = User.create!(name: 'Joiner', email: 'joiner@example.com')
    ActionMailer::Base.deliveries.clear

    assert_difference -> { MagicLink.where(purpose: :join).count } => 1,
                      -> { ActionMailer::Base.deliveries.size } => 1 do
      post complete_join_path, params: { signed_kitchen_id: signed, email: joiner.email }
    end

    assert_redirected_to sessions_magic_link_path

    link = MagicLink.order(:created_at).last

    assert_equal kitchen_being_joined, link.kitchen
    assert_equal 'join', link.purpose
    assert_equal joiner, link.user
    assert_nil ActsAsTenant.with_tenant(kitchen_being_joined) { Membership.find_by(user: joiner) }
  end

  test 'POST /join/complete with new email creates User, magic link, and mail' do
    kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
    signed = sign_kitchen_id(kitchen_being_joined.id)
    ActionMailer::Base.deliveries.clear

    assert_difference -> { User.count } => 1, -> { MagicLink.count } => 1 do
      post complete_join_path,
           params: { signed_kitchen_id: signed, email: 'new@example.com', name: 'New Person' }
    end

    assert_redirected_to sessions_magic_link_path
    new_user = User.find_by(email: 'new@example.com')

    assert_equal 'New Person', new_user.name
  end

  test 'POST /join/complete with missing name re-renders the name form' do
    kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
    signed = sign_kitchen_id(kitchen_being_joined.id)

    assert_no_difference -> { MagicLink.count } do
      post complete_join_path, params: { signed_kitchen_id: signed, email: 'new@example.com' }
    end

    assert_response :success
    assert_select 'input[name=name]'
  end

  test 'POST /join/complete sets pending_auth cookie' do
    kitchen_being_joined = Kitchen.create!(name: 'Another Kitchen', slug: 'another-kitchen')
    signed = sign_kitchen_id(kitchen_being_joined.id)
    User.create!(name: 'Joiner', email: 'joiner@example.com')

    post complete_join_path, params: { signed_kitchen_id: signed, email: 'joiner@example.com' }

    assert_not_empty cookies[:pending_auth].to_s
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
