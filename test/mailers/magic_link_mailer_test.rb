# frozen_string_literal: true

require 'test_helper'

class MagicLinkMailerTest < ActionMailer::TestCase
  setup do
    create_kitchen_and_user
    @magic_link = MagicLink.create!(
      user: @user,
      purpose: :sign_in,
      expires_at: 15.minutes.from_now,
      request_ip: '10.0.0.5',
      request_user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14)'
    )
  end

  test 'sign_in_instructions sets headers' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)

    assert_equal [@user.email], mail.to
    assert_equal 'Sign in to Family Recipes', mail.subject
    assert_equal ['no-reply@localhost'], mail.from
  end

  test 'sign_in_instructions renders the code in both parts' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)

    assert_includes mail.html_part.body.to_s, @magic_link.code
    assert_includes mail.text_part.body.to_s, @magic_link.code
  end

  test 'sign_in_instructions renders the request metadata' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)
    body = mail.text_part.body.to_s

    assert_includes body, '10.0.0.5'
    assert_includes body, 'Macintosh'
  end

  test 'sign_in_instructions renders a code-bearing URL' do
    mail = MagicLinkMailer.sign_in_instructions(@magic_link)
    body = mail.html_part.body.to_s

    assert_includes body, "code=#{@magic_link.code}"
  end
end
