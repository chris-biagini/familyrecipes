# frozen_string_literal: true

# Encapsulates the signed `:pending_auth` cookie carrying the normalized
# email between /sessions/new -> /sessions/magic_link and between
# /join -> /sessions/magic_link. The cookie is signed with
# MessageVerifier, purpose :pending_auth, 15-minute expiry, so it cannot
# be forged without secret_key_base. The email is what
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
  PENDING_AUTH_PURPOSE = :pending_auth

  # rubocop:disable Naming/AccessorMethodName -- not a writer; signs+expires, paired with `pending_auth_email` reader
  def set_pending_auth_email(email)
    token = Rails.application.message_verifier(:pending_auth).generate(
      email, purpose: PENDING_AUTH_PURPOSE, expires_in: PENDING_AUTH_EXPIRY
    )
    cookies.signed[:pending_auth] = { value: token, httponly: true, same_site: :lax }
  end
  # rubocop:enable Naming/AccessorMethodName

  def pending_auth_email
    raw = cookies.signed[:pending_auth]
    return nil if raw.blank?

    Rails.application.message_verifier(:pending_auth).verified(raw, purpose: PENDING_AUTH_PURPOSE)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def clear_pending_auth
    cookies.delete(:pending_auth)
  end
end
