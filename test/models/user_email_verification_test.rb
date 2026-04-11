# frozen_string_literal: true

require 'test_helper'

class UserEmailVerificationTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
    @user.update!(email_verified_at: nil)
  end

  test 'email_verified? is false when the column is nil' do
    assert_not_predicate @user, :email_verified?
  end

  test 'verify_email! sets email_verified_at to the current time' do
    freeze_time do
      @user.verify_email!

      assert_equal Time.current, @user.email_verified_at
    end
  end

  test 'verify_email! is a no-op when already verified' do
    @user.update!(email_verified_at: 3.days.ago)
    previous = @user.email_verified_at

    @user.verify_email!

    assert_equal previous, @user.reload.email_verified_at
  end

  test 'email_verified? is true when the column is set' do
    @user.update!(email_verified_at: Time.current)

    assert_predicate @user, :email_verified?
  end
end
