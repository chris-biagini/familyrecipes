# frozen_string_literal: true

# Kitchen creation flow. Creates a Kitchen, User, Membership (owner role),
# and MealPlan in a single transaction, then starts a session. Ungated in
# Phase 1 (beta); Phase 2 adds email verification for hosted mode.
#
# - Kitchen: tenant model with join_code generation
# - User: found or created by email
# - Membership: join table with role column
# - Authentication concern: start_new_session_for
class KitchensController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :redirect_if_logged_in, only: :new

  layout 'auth'

  rate_limit to: 5, within: 1.hour, by: -> { request.remote_ip }, only: :create

  def new
    # Form rendered by view
  end

  def create
    kitchen = nil
    user = nil

    ActiveRecord::Base.transaction do
      kitchen = build_kitchen
      user = find_or_create_user
      ActsAsTenant.with_tenant(kitchen) do
        Membership.create!(kitchen: kitchen, user: user, role: 'owner')
        MealPlan.create!(kitchen: kitchen)
      end
    end

    start_new_session_for(user)
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  private

  def build_kitchen
    Kitchen.create!(
      name: params[:kitchen_name],
      slug: params[:kitchen_name].to_s.parameterize.presence || 'kitchen'
    )
  end

  def find_or_create_user
    User.find_or_create_by!(email: params[:email].to_s.strip.downcase) do |u|
      u.name = params[:name]
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def redirect_if_logged_in
    return unless authenticated?
    return if params[:intentional]

    redirect_to root_path
  end
end
