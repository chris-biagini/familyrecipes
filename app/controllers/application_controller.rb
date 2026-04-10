# frozen_string_literal: true

# Central before_action pipeline: resume session → authenticate from trusted
# headers (Authelia, Authentik, oauth2-proxy, etc.) → auto-login in dev →
# set tenant from path. Public reads are allowed (allow_unauthenticated_access);
# write paths and member-only pages call require_membership. Also manages
# the optional kitchen_slug URL scope and cache headers for member-only pages.
#
# Trusted-header auth (defense in depth): every request that carries the
# configured Remote-User header is subject to a per-request peer IP check
# against Rails.configuration.trusted_proxy_config. If the TCP peer is not
# in the allowlist (default: 127.0.0.0/8, ::1/128) the headers are ignored
# and the request falls through to anonymous/passwordless. This protects
# against reverse-proxy misconfigurations that leak inbound Remote-* headers
# from external requests. Operators running a proxy on a separate host or
# different docker network must widen the allowlist via TRUSTED_PROXY_IPS;
# operators who cannot guarantee header stripping can disable the path
# entirely with TRUSTED_PROXY_IPS= (empty). See README "Disabling
# trusted-header auth".
#
# Trusted-header auto-join: when trusted headers identify a brand-new user
# (zero memberships) and exactly one Kitchen exists, the user is auto-joined
# to that kitchen as a member. Restricted by the peer IP gate above.
#
# Collaborators:
# - Authentication concern: session lifecycle (resume, start, terminate)
# - FamilyRecipes::TrustedProxyConfig: peer IP + header name resolution
# - Kitchen / acts_as_tenant: multi-tenant scoping via set_current_tenant
# - User / Membership: trusted-header user lookup and auto-join
class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  set_current_tenant_through_filter
  before_action :resume_session
  before_action :authenticate_from_headers
  before_action :auto_login_in_development
  before_action :set_kitchen_from_path
  after_action :flush_broadcast
  helper_method :current_kitchen, :current_member?, :logged_in?, :home_path, :versioned_icon_path

  private

  def set_kitchen_from_path
    if params[:kitchen_slug]
      set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
      return
    end

    kitchen = resolve_sole_kitchen
    if kitchen
      set_current_tenant(kitchen)
    else
      redirect_to root_path
    end
  end

  def resolve_sole_kitchen
    kitchens = ActsAsTenant.without_tenant { Kitchen.limit(2).to_a }
    kitchens.first if kitchens.size == 1
  end

  def current_kitchen = ActsAsTenant.current_tenant

  def logged_in? = authenticated?

  def home_path(**)
    params[:kitchen_slug] ? kitchen_root_path(**) : root_path(**)
  end

  def versioned_icon_path(filename)
    "/icons/#{filename}?v=#{Rails.configuration.icon_version}"
  end

  def authenticate_from_headers
    return if authenticated?

    cfg = Rails.application.config.trusted_proxy_config
    return unless cfg.allow?(request.remote_ip)

    identity = trusted_header_identity(cfg)
    return unless identity

    user = User.find_or_create_by!(email: identity[:email]) { |u| u.name = identity[:name] }
    start_new_session_for(user)
    auto_join_sole_kitchen(user)
  end

  def trusted_header_identity(cfg)
    # Must use request.env, not request.headers — 'Remote-User' collides with
    # the CGI REMOTE_USER variable, so request.headers['Remote-User'] is unreliable.
    env = request.env
    remote_user = env[cfg.user_header]
    return if remote_user.blank?

    { email: env[cfg.email_header].presence || "#{remote_user}@header.local",
      name: env[cfg.name_header].presence || remote_user }
  end

  def auto_join_sole_kitchen(user)
    ActsAsTenant.without_tenant do
      return if Membership.exists?(user_id: user.id)
      return unless Kitchen.limit(2).one?

      Membership.create!(kitchen: Kitchen.first, user: user, role: 'member')
    end
  end

  def auto_login_in_development
    return unless Rails.env.development?
    return if authenticated?
    return if cookies[:skip_dev_auto_login]

    user = User.first
    return unless user

    start_new_session_for(user)
  end

  def current_member?
    return @current_member if defined?(@current_member)

    @current_member = current_kitchen&.member?(current_user)
  end

  def require_membership
    return head(:forbidden) unless logged_in?

    head(:forbidden) unless current_member?
  end

  def default_url_options
    return { kitchen_slug: params[:kitchen_slug] } if params[:kitchen_slug]

    {}
  end

  def prevent_html_caching
    response.headers['Cache-Control'] = 'private, no-cache'
  end

  def flush_broadcast
    kitchen = Current.broadcast_pending
    return unless kitchen

    Current.broadcast_pending = nil
    kitchen.broadcast_update
  end

  def record_not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join('404.html'), status: :not_found, layout: false }
      format.json { head :not_found }
      format.text { head :not_found }
    end
  end
end
