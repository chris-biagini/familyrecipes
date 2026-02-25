# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  set_current_tenant_through_filter
  before_action :resume_session
  before_action :authenticate_from_headers
  before_action :auto_join_sole_kitchen
  before_action :set_kitchen_from_path

  helper_method :current_kitchen, :logged_in?

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]

    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_kitchen = ActsAsTenant.current_tenant

  def logged_in? = authenticated?

  def authenticate_from_headers
    return if authenticated?

    remote_user = request.headers['Remote-User']
    return unless remote_user

    email = request.headers['Remote-Email'] || "#{remote_user}@header.local"
    name = request.headers['Remote-Name'] || remote_user

    user = User.find_or_create_by!(email: email) do |u|
      u.name = name
    end

    start_new_session_for(user)
  end

  def auto_join_sole_kitchen
    return unless authenticated?

    user = current_user
    return if ActsAsTenant.without_tenant { user.memberships.exists? }

    kitchens = ActsAsTenant.without_tenant { Kitchen.all }
    return unless kitchens.size == 1

    ActsAsTenant.with_tenant(kitchens.first) do
      Membership.create!(kitchen: kitchens.first, user: user)
    end
  end

  def require_membership
    unless logged_in?
      return head(:forbidden) if request.format.json?

      return request_authentication
    end

    head(:forbidden) unless current_kitchen&.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
