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

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip },
             with: lambda {
               log_rate_limited
               head(:too_many_requests)
             }, only: :create

  def new
    redirect_to root_path if authenticated?
  end

  def create
    email = normalize_email(params[:email])
    return redirect_to new_session_path, alert: 'Please enter an email address.' if email.blank?

    issue_magic_link_for(email)
    set_pending_auth_email(email)
    redirect_to sessions_magic_link_path
  end

  def destroy
    terminate_session
    redirect_to root_path, notice: "You've been signed out."
  end

  private

  def normalize_email(raw)
    raw.to_s.strip.downcase.presence
  end

  def issue_magic_link_for(email)
    user = User.find_by(email:)
    has_membership = user && ActsAsTenant.without_tenant { user.memberships.any? }
    return SecurityEventLogger.log(:unknown_email_auth_attempt, email:) unless has_membership

    deliver_sign_in_link(user)
  end

  def deliver_sign_in_link(user)
    link = MagicLink.create!(
      user: user, purpose: :sign_in, expires_at: 15.minutes.from_now,
      request_ip: request.remote_ip, request_user_agent: request.user_agent
    )
    SecurityEventLogger.log(:magic_link_issued, user_id: user.id, purpose: :sign_in)
    MagicLinkMailer.sign_in_instructions(link).deliver_later
  end

  def log_rate_limited
    SecurityEventLogger.log(:rate_limited,
                            controller: controller_name, action: action_name, ip: request.remote_ip)
  end
end
