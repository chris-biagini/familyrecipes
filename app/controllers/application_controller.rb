# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  set_current_tenant_through_filter
  before_action :resume_session
  before_action :authenticate_from_headers
  before_action :auto_login_in_development
  before_action :auto_join_sole_kitchen
  before_action :set_kitchen_from_path

  helper_method :current_kitchen, :logged_in?, :home_path

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

  def authenticate_from_headers
    return if authenticated?

    remote_user = request.env['HTTP_REMOTE_USER']
    return if remote_user.blank?

    email = request.env['HTTP_REMOTE_EMAIL'].presence || "#{remote_user}@header.local"
    name = request.env['HTTP_REMOTE_NAME'].presence || remote_user

    user = User.find_or_create_by!(email: email) do |u|
      u.name = name
    end

    start_new_session_for(user)
  end

  def auto_login_in_development
    return unless Rails.env.development?
    return if authenticated?
    return if cookies[:skip_dev_auto_login]

    user = User.first
    return unless user

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
    return head(:forbidden) unless logged_in?

    head(:forbidden) unless current_kitchen&.member?(current_user)
  end

  def default_url_options
    return { kitchen_slug: params[:kitchen_slug] } if params[:kitchen_slug]

    {}
  end

  def record_not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join('404.html'), status: :not_found, layout: false }
      format.json { head :not_found }
    end
  end
end
