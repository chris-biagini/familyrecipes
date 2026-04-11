# frozen_string_literal: true

# Email-first authentication front door. `new` renders a single-field form;
# `create` accepts an email, issues a MagicLink (or renders the same
# "check your email" response for unknown emails for anti-enumeration),
# and stores the pending email in a signed cookie. Code consumption is
# handled by MagicLinksController. `destroy` ends the session and
# redirects to root — no interstitial.
#
# - User: looked up by email
# - MagicLink: created on the sign-in code path
# - MagicLinkMailer: delivers the code
# - PendingAuthToken concern: signed cookie carrying the typed email
# - Authentication concern: terminate_session
class SessionsController < ApplicationController
  include PendingAuthToken

  skip_before_action :set_kitchen_from_path

  layout 'auth'

  def new
    redirect_to root_path if authenticated?
  end

  def destroy
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
    redirect_to root_path, notice: "You've been signed out."
  end
end
