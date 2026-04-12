# frozen_string_literal: true

# Central before_action pipeline: resume session -> set tenant from path.
# Public reads are allowed (allow_unauthenticated_access); write paths and
# member-only pages call require_membership. Also manages the optional
# kitchen_slug URL scope and cache headers for member-only pages.
#
# Collaborators:
# - Authentication concern: session lifecycle (resume, start, terminate)
# - Kitchen / acts_as_tenant: multi-tenant scoping via set_current_tenant
# - User / Membership: session-bound identity
class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  set_current_tenant_through_filter
  before_action :resume_session
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
