# frozen_string_literal: true

require 'test_helper'

class SettingsJoinCodeTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    @kitchen.memberships.find_by(user: @user).update!(role: 'owner')
    log_in
  end

  test 'settings JSON includes join_code and members' do
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    json = response.parsed_body

    assert_predicate json['join_code'], :present?
    assert_kind_of Array, json['members']
    assert_equal 1, json['members'].size
    assert_equal @user.name, json['members'].first['name']
  end

  test 'settings JSON includes current user info' do
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    json = response.parsed_body

    assert_equal @user.name, json['current_user_name']
    assert_equal @user.email, json['current_user_email']
  end

  test 'regenerate_join_code changes the code' do
    old_code = @kitchen.join_code

    post settings_regenerate_join_code_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    @kitchen.reload

    assert_not_equal old_code, @kitchen.join_code
  end

  test 'regenerate_join_code requires owner role' do
    member_user = User.create!(name: 'Member', email: 'member@example.com')
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: member_user, role: 'member')
    end
    get dev_login_path(id: member_user.id)

    post settings_regenerate_join_code_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'update_profile changes user name and email' do
    patch settings_profile_path(kitchen_slug: kitchen_slug),
          params: { user: { name: 'New Name', email: 'newemail@example.com' } },
          as: :json

    assert_response :success
    @user.reload

    assert_equal 'New Name', @user.name
    assert_equal 'newemail@example.com', @user.email
  end

  test 'update_profile rejects invalid email' do
    patch settings_profile_path(kitchen_slug: kitchen_slug),
          params: { user: { name: 'Valid', email: 'not-an-email' } },
          as: :json

    assert_response :unprocessable_content
    json = response.parsed_body

    assert_includes json['errors'], 'Email is invalid'
  end

  test 'editor_frame includes join code field' do
    get settings_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "input[data-settings-editor-target='joinCode']" do |inputs|
      assert_equal @kitchen.join_code, inputs.first['value']
    end
  end

  test 'editor_frame shows regenerate button for owners' do
    get settings_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "button[data-action='settings-editor#regenerateJoinCode']"
  end

  test 'editor_frame hides regenerate button for members' do
    member_user = User.create!(name: 'Member', email: 'member@example.com')
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: member_user, role: 'member')
    end
    get dev_login_path(id: member_user.id)

    get settings_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "button[data-action='settings-editor#regenerateJoinCode']", count: 0
  end

  test 'editor_frame includes profile fields' do
    get settings_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select "input[data-settings-editor-target='profileName']" do |inputs|
      assert_equal @user.name, inputs.first['value']
    end
    assert_select "input[data-settings-editor-target='profileEmail']" do |inputs|
      assert_equal @user.email, inputs.first['value']
    end
  end

  test 'editor_frame lists members' do
    get settings_editor_frame_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '.settings-members-list li', count: 1
    assert_select '.member-name', text: @user.name
  end
end
