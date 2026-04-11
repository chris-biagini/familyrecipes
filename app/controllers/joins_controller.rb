# frozen_string_literal: true

# Step 1 of the invitation flow: visitor enters a join code, which we
# validate and use to issue a :join magic link. Membership creation is
# deferred to MagicLinksController#create so the "no membership without
# verified email" invariant lives in one place.
#
# - Kitchen: join code lookup
# - MagicLink: created with purpose: :join and the target kitchen
# - MagicLinkMailer: delivers the 6-character code
# - PendingAuthToken concern: signed cookie carrying the typed email
class JoinsController < ApplicationController
  include PendingAuthToken

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
      return redirect_to join_kitchen_path,
                         alert: 'Invalid or expired session. Please re-enter your join code.'
    end

    email = normalize_email(params[:email])
    return redirect_to join_kitchen_path, alert: 'Please enter your email.' if email.blank?

    return render_name_form(kitchen, email) if new_user_missing_name?(email)

    issue_join_link(kitchen, email)
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render_name_form(kitchen, email)
  end

  private

  def normalize_email(raw)
    raw.to_s.strip.downcase.presence
  end

  def new_user_missing_name?(email)
    params[:name].blank? && ActsAsTenant.without_tenant { User.find_by(email:) }.nil?
  end

  def issue_join_link(kitchen, email)
    user = find_or_create_user(email)
    link = create_join_link(user, kitchen)
    MagicLinkMailer.sign_in_instructions(link).deliver_now
    set_pending_auth_email(email)
    redirect_to sessions_magic_link_path
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def find_or_create_user(email)
    ActsAsTenant.without_tenant do
      User.find_or_create_by!(email:) do |u|
        u.name = params[:name].to_s.presence || email.split('@').first
      end
    end
  end

  def create_join_link(user, kitchen)
    MagicLink.create!(
      user:,
      kitchen:,
      purpose: :join,
      expires_at: 15.minutes.from_now,
      request_ip: request.remote_ip,
      request_user_agent: request.user_agent
    )
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
    kitchen_id = Rails.application.message_verifier(:join).verified(
      params[:signed_kitchen_id], purpose: :join
    )
    return nil unless kitchen_id

    ActsAsTenant.without_tenant { Kitchen.find_by(id: kitchen_id) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
