# frozen_string_literal: true

# Encapsulates the encrypted `:pending_auth` cookie carrying the normalized
# email between /sessions/new -> /sessions/magic_link and between
# /join -> /sessions/magic_link. Encrypted (AES-GCM via cookies.encrypted)
# so the email payload isn't readable even with a cookie dump; 15-minute
# expiry enforced by the cookie jar. The email is what
# MagicLinksController#create cross-checks against the consumed magic
# link's user email to prevent a passerby hijacking a half-finished
# sign-in with a code obtained elsewhere.
#
# - SessionsController: sets the cookie after issuing a magic link
# - JoinsController: sets the cookie after issuing a :join magic link
# - MagicLinksController: reads it in the before_action and clears it on consume
module PendingAuthToken
  extend ActiveSupport::Concern

  PENDING_AUTH_EXPIRY = 15.minutes

  # rubocop:disable Naming/AccessorMethodName -- not a writer; encrypts+expires, paired with `pending_auth_email` reader
  def set_pending_auth_email(email)
    cookies.encrypted[:pending_auth] = {
      value: email,
      expires: PENDING_AUTH_EXPIRY.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end
  # rubocop:enable Naming/AccessorMethodName

  def pending_auth_email
    cookies.encrypted[:pending_auth].presence
  end

  def clear_pending_auth
    cookies.delete(:pending_auth)
  end
end
