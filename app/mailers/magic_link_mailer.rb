# frozen_string_literal: true

# Delivers short-lived sign-in codes to users. One action,
# sign_in_instructions, takes a MagicLink record and renders both HTML
# and text parts containing the 6-character code, a one-click link, the
# expiry, and the IP / user-agent of the request that issued it. Operators
# without SMTP get the full email in the Rails log (see
# config/environments/production.rb).
#
# - MagicLink: the record being delivered
# - MagicLinksController: receives the code for consumption
class MagicLinkMailer < ApplicationMailer
  def sign_in_instructions(magic_link)
    @magic_link = magic_link
    @code = magic_link.code
    @login_url = sessions_magic_link_url(code: magic_link.code)
    @expires_in_minutes = 15
    @request_ip = magic_link.request_ip
    @request_user_agent = magic_link.request_user_agent

    mail to: magic_link.user.email, subject: 'Sign in to Family Recipes'
  end
end
