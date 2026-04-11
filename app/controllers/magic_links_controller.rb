# frozen_string_literal: true

# Consumes short-lived magic link codes issued by SessionsController or
# JoinsController. `new` renders the code-entry form (after the user has
# hit /sessions/new with an email). `create` consumes the code atomically,
# verifies the consumed link's user email against the signed pending_auth
# cookie, starts a session, and redirects to the user's kitchen.
# `:join` purpose links also create a Membership on consume.
#
# - MagicLink: the consumed record
# - User: the authenticated identity (verify_email! on first consume)
# - PendingAuthToken concern: reads and clears the pending_auth cookie
# - Authentication concern: start_new_session_for
class MagicLinksController < ApplicationController
  include PendingAuthToken

  skip_before_action :set_kitchen_from_path
  before_action :require_pending_auth

  layout 'auth'

  def new
    @masked_email = mask_email(pending_auth_email)
  end

  private

  def require_pending_auth
    return if pending_auth_email.present?

    redirect_to new_session_path, alert: 'Please start by entering your email.'
  end

  def mask_email(email)
    return '' if email.blank?

    _local, domain = email.split('@', 2)
    "…@#{domain}"
  end
end
