# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle),
# display preferences, join code management, member listing, and user
# profile editing. The settings dialog loads its form via a Turbo Frame
# (editor_frame) and saves via JSON PATCH. Join code regeneration is
# restricted to kitchen owners.
#
# - Kitchen: settings live as columns on the tenant model
# - ApplicationController: provides current_kitchen, current_user, require_membership
# - Membership: role-based access (owner vs member)
class SettingsController < ApplicationController
  before_action :require_membership

  def show
    render json: {
      site_title: current_kitchen.site_title,
      homepage_heading: current_kitchen.homepage_heading,
      homepage_subtitle: current_kitchen.homepage_subtitle,
      show_nutrition: current_kitchen.show_nutrition,
      decorate_tags: current_kitchen.decorate_tags,
      join_code: current_kitchen.join_code,
      members: member_list,
      current_user_name: current_user.name,
      current_user_email: current_user.email
    }
  end

  def editor_frame
    render partial: 'settings/editor_frame',
           locals: { kitchen: current_kitchen, owner: owner?, members: member_list, current_user_record: current_user },
           layout: false
  end

  def update
    if current_kitchen.update(settings_params)
      current_kitchen.broadcast_update
      render json: { status: 'ok' }
    else
      render json: { errors: current_kitchen.errors.full_messages }, status: :unprocessable_content
    end
  end

  def regenerate_join_code
    return head(:forbidden) unless owner?

    current_kitchen.regenerate_join_code!
    render json: { join_code: current_kitchen.join_code }
  end

  def update_profile
    if current_user.update(profile_params)
      render json: { status: 'ok' }
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def owner?
    current_kitchen.memberships.exists?(user: current_user, role: 'owner')
  end

  def member_list
    ActsAsTenant.with_tenant(current_kitchen) do
      current_kitchen.memberships.includes(:user).map do |m|
        { id: m.user_id, name: m.user.name, email: m.user.email, role: m.role }
      end
    end
  end

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle
                              show_nutrition decorate_tags])
  end

  def profile_params
    params.expect(user: %i[name email])
  end
end
