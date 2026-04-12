# frozen_string_literal: true

# Device-to-device session transfer. `create` generates a short-lived,
# signed QR code so a logged-in member can scan it on another device;
# `show` consumes the token and starts a session on the new device.
# One token type: `:transfer` (self, 5 min, QR code). Kitchen context
# is passed as a query param (?k=slug) and verified against the user's
# memberships before creating a session.
#
# - Authentication concern: start_new_session_for, require_authentication
# - User: signed_id / find_signed (Rails built-in)
# - Kitchen: membership verification
# - Settings dialog: triggers create via a Turbo Frame form
class TransfersController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_authentication, only: :create

  layout 'auth', only: :show

  def show
    user = resolve_token
    kitchen = resolve_kitchen(user)

    unless user && kitchen
      SecurityEventLogger.log(:transfer_token_consume_failed,
                              reason: user ? :kitchen_membership_missing : :invalid_token)
      @error = 'This link is invalid or has expired.'
      return render :show_error, status: :unprocessable_content
    end

    SecurityEventLogger.log(:transfer_token_consumed, user_id: user.id, kitchen_id: kitchen.id)
    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def create
    token = current_user.signed_id(purpose: :transfer, expires_in: 5.minutes)
    kitchen_slug = params[:kitchen_slug]
    @transfer_url = show_transfer_url(token:, k: kitchen_slug)
    @qr_svg = generate_qr_svg(@transfer_url)
    render layout: false
  end

  private

  def resolve_token
    User.find_signed(params[:token], purpose: :transfer)
  end

  def generate_qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(
      shape_rendering: 'crispEdges',
      module_size: 4,
      viewbox: true,
      use_path: true
    )
  end

  def resolve_kitchen(user)
    return nil unless user

    slug = params[:k]
    return nil unless slug

    kitchen = ActsAsTenant.without_tenant { Kitchen.find_by(slug:) }
    return nil unless kitchen

    member = ActsAsTenant.with_tenant(kitchen) { kitchen.member?(user) }
    member ? kitchen : nil
  end
end
