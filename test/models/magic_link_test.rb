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

  test 'generate_code returns a 6-character string from the restricted alphabet' do
    100.times do
      code = MagicLink.generate_code

      assert_equal 6, code.length
      assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, code)
    end
  end

  test 'code is auto-assigned on create when blank' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)

    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, link.code)
  end

  test 'code is unique across creates' do
    codes = Array.new(50) do
      MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now).code
    end

    assert_equal codes.uniq.size, codes.size
  end

  test 'consume returns the link and marks it consumed' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    result = MagicLink.consume(link.code)

    assert_equal link.id, result.id
    assert_not_nil result.consumed_at
  end

  test 'consume returns nil for unknown code' do
    assert_nil MagicLink.consume('ZZZZZZ')
  end

  test 'consume returns nil for expired code' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 1.minute.ago)

    assert_nil MagicLink.consume(link.code)
  end

  test 'consume returns nil when code is already consumed' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    MagicLink.consume(link.code)

    assert_nil MagicLink.consume(link.code)
  end

  test 'consume normalizes the input code (whitespace and case)' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)
    result = MagicLink.consume("  #{link.code.downcase}  ")

    assert_equal link.id, result.id
  end

  test 'consume is atomic under concurrent attempts' do
    link = MagicLink.create!(user: @user, purpose: :sign_in, expires_at: 15.minutes.from_now)

    results = Array.new(5) do
      Thread.new { MagicLink.consume(link.code) }
    end.map(&:value)

    successes = results.compact

    assert_equal 1, successes.size
  end
end
