# frozen_string_literal: true

# Preview magic link email templates at /rails/mailers in development.
class MagicLinkMailerPreview < ActionMailer::Preview
  def sign_in_instructions
    kitchen = Kitchen.first
    user = User.first
    raise 'Seed a kitchen/user first: bin/rails db:seed' unless kitchen && user

    link = MagicLink.new(
      user: user,
      kitchen: kitchen,
      purpose: :sign_in,
      code: 'ABCD23',
      expires_at: 15.minutes.from_now,
      request_ip: '10.0.0.5',
      request_user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)'
    )

    MagicLinkMailer.sign_in_instructions(link)
  end
end
