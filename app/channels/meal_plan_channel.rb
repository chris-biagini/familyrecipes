# frozen_string_literal: true

# ActionCable channel for real-time meal plan sync across devices. Broadcasts
# version numbers on state changes (selections, checks, custom items) so clients
# can poll for fresh state when stale. Also broadcasts content_changed events
# when recipes, quick bites, or aisle mappings change — clients show a reload
# prompt. Both menu and groceries pages subscribe to the same channel. Must wrap
# MealPlan.for_kitchen in ActsAsTenant.with_tenant because channel methods don't
# inherit the controller's tenant context.
class MealPlanChannel < ApplicationCable::Channel
  def subscribed
    kitchen = Kitchen.find_by(slug: params[:kitchen_slug])
    return reject unless authorized?(kitchen)

    stream_for kitchen
    ActsAsTenant.with_tenant(kitchen) do
      self.class.broadcast_version(kitchen, MealPlan.for_kitchen(kitchen).lock_version)
    end
  end

  def self.broadcast_version(kitchen, version)
    broadcast_to(kitchen, version: version)
  end

  def self.broadcast_content_changed(kitchen)
    broadcast_to(kitchen, type: 'content_changed')
  end

  private

  def authorized?(kitchen)
    return false unless kitchen

    ActsAsTenant.with_tenant(kitchen) { kitchen.member?(current_user) }
  end
end
