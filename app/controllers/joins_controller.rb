# frozen_string_literal: true

# Multi-step join flow: enter join code -> enter email -> re-auth or register.
# Handles both new member registration and returning member re-authentication
# through a single unified flow. Kitchen ID is passed between steps via a
# signed, time-limited token to prevent tampering.
#
# - Kitchen: join code lookup via find_by_join_code
# - User: found or created by email
# - Membership: join table creation for new members
# - Authentication concern: start_new_session_for
class JoinsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  layout 'auth'

  rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, only: :verify

  def new; end

  def verify
    kitchen = Kitchen.find_by_join_code(params[:join_code])

    unless kitchen
      @error = "That code doesn't match any kitchen. Double-check and try again."
      return render :new, status: :unprocessable_content
    end

    @signed_kitchen_id = sign_kitchen_id(kitchen.id)
    @kitchen_name = kitchen.name
    render :verify
  end

  def create
    kitchen = resolve_signed_kitchen
    unless kitchen
      return redirect_to join_kitchen_path, alert: 'Invalid or expired session. Please re-enter your join code.'
    end

    email = params[:email].to_s.strip.downcase
    authenticate_or_register(kitchen, email)
  end

  private

  def authenticate_or_register(kitchen, email)
    user = User.find_by(email: email)

    return authenticate_existing(kitchen, user) if user
    return render_name_form(kitchen, email) if params[:name].blank?

    register_new_member(kitchen, email, params[:name])
  end

  def authenticate_existing(kitchen, user)
    ensure_membership(kitchen, user)
    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def ensure_membership(kitchen, user)
    return if ActsAsTenant.with_tenant(kitchen) { kitchen.member?(user) }

    ActsAsTenant.with_tenant(kitchen) { Membership.create!(kitchen: kitchen, user: user) }
  end

  def register_new_member(kitchen, email, name)
    user = User.create!(name: name, email: email)
    ActsAsTenant.with_tenant(kitchen) { Membership.create!(kitchen: kitchen, user: user) }
    start_new_session_for(user)
    signed_k = Rails.application.message_verifier(:welcome).generate(kitchen.id, purpose: :welcome,
                                                                                 expires_in: 15.minutes)
    redirect_to welcome_path(k: signed_k)
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render_name_form(kitchen, email)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def render_name_form(kitchen, email)
    @signed_kitchen_id = sign_kitchen_id(kitchen.id)
    @kitchen_name = kitchen.name
    @email = email
    render :name
  end

  def sign_kitchen_id(id)
    Rails.application.message_verifier(:join).generate(id, purpose: :join, expires_in: 15.minutes)
  end

  def resolve_signed_kitchen
    kitchen_id = Rails.application.message_verifier(:join).verified(params[:signed_kitchen_id], purpose: :join)
    return nil unless kitchen_id

    ActsAsTenant.without_tenant { Kitchen.find_by(id: kitchen_id) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
