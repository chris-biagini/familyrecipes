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

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip },
             with: lambda {
               log_rate_limited
               head(:too_many_requests)
             }, only: :create

  def new
    @masked_email = mask_email(pending_auth_email)
  end

  def create
    link = MagicLink.consume(params[:code])
    unless link && pending_auth_email == link.user.email
      SecurityEventLogger.log(:magic_link_consume_failed,
                              reason: link ? :email_mismatch : :invalid_or_expired)
      return render_invalid
    end

    link.user.verify_email!
    ensure_join_membership(link) if link.join?
    start_new_session_for(link.user)
    clear_pending_auth

    SecurityEventLogger.log(:magic_link_consumed, user_id: link.user.id, purpose: link.purpose)
    redirect_to after_sign_in_path_for(link)
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

  def render_invalid
    flash.now[:alert] = 'Invalid or expired code. Try again or start over.'
    @masked_email = mask_email(pending_auth_email)
    render :new, status: :unprocessable_content
  end

  def ensure_join_membership(link)
    ActsAsTenant.with_tenant(link.kitchen) do
      Membership.find_or_create_by!(kitchen: link.kitchen, user: link.user) do |m|
        m.role = 'member'
      end
    end
  end

  def after_sign_in_path_for(link)
    kitchen = link.kitchen || ActsAsTenant.without_tenant { link.user.kitchens.first }
    return root_path unless kitchen

    kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def log_rate_limited
    SecurityEventLogger.log(:rate_limited,
                            controller: controller_name, action: action_name, ip: request.remote_ip)
  end
end
