# frozen_string_literal: true

require 'test_helper'

class MagicLinkTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
  end

  test 'belongs to user and optional kitchen' do
    link = MagicLink.new(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now, code: 'ABCD23')

    assert_predicate link, :valid?
    assert_equal @user, link.user
    assert_nil link.kitchen
  end
end
