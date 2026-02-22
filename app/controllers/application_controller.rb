# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  set_current_tenant_through_filter
  before_action :set_kitchen_from_path

  helper_method :current_user, :current_kitchen, :logged_in?

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]

    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_kitchen
    ActsAsTenant.current_tenant
  end

  def logged_in?
    current_user.present?
  end

  def require_membership
    head :unauthorized unless logged_in? && current_kitchen&.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
