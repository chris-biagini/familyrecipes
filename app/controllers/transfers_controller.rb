# frozen_string_literal: true

# Generates and consumes signed, time-limited tokens for re-authentication.
# Two token types: :transfer (self, 5 min, QR code) and :login (member-to-member,
# 24 hours, copyable link). Both are consumed via the same show action using
# User#find_signed. Kitchen context is passed as a query param (?k=slug) and
# verified against the user's memberships before creating a session.
#
# - Authentication concern: start_new_session_for, require_authentication
# - User: signed_id / find_signed (Rails built-in)
# - Kitchen: membership verification
# - Settings dialog: triggers create/create_for_member via Turbo Frame forms
class TransfersController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_authentication, only: %i[create create_for_member]

  layout 'auth', only: :show

  def show
    user = resolve_token
    kitchen = resolve_kitchen(user)

    unless user && kitchen
      @error = 'This link is invalid or has expired.'
      return render :show_error, status: :unprocessable_content
    end

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

  def create_for_member
    kitchen = resolve_current_kitchen
    return head(:forbidden) unless ActsAsTenant.with_tenant(kitchen) { kitchen.member?(current_user) }

    target = find_kitchen_member(kitchen)
    return head(:not_found) unless target

    token = target.signed_id(purpose: :login, expires_in: 24.hours)
    @login_link_url = show_transfer_url(token:, k: kitchen.slug)
    render layout: false
  end

  private

  def resolve_token
    User.find_signed(params[:token], purpose: :transfer) ||
      User.find_signed(params[:token], purpose: :login)
  end

  def generate_qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(
      shape_rendering: 'crispEdges',
      module_size: 4,
      standalone: true,
      use_path: true
    )
  end

  def resolve_current_kitchen
    slug = params[:kitchen_slug]
    ActsAsTenant.without_tenant { Kitchen.find_by!(slug:) }
  end

  def find_kitchen_member(kitchen)
    ActsAsTenant.with_tenant(kitchen) do
      user = User.find_by(id: params[:id])
      return nil unless user && kitchen.member?(user)

      user
    end
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
