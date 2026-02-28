# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipeBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @user = User.find_or_create_by!(email: 'test@example.com') { |u| u.name = 'Test' }
    Membership.find_or_create_by!(kitchen: @kitchen, user: @user)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple bread.

      Category: Bread

      ## Dough

      - Flour, 3 cups
      - Water, 1 cup

      Mix and knead.
    MD
  end

  test 'broadcasts Turbo Streams to kitchen recipes stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'recipes'] do
      RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
    end
  end

  test 'broadcasts content_changed via MealPlanChannel' do
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
    end
  end

  test 'broadcasts to recipe-specific stream when recipe provided' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.broadcast(
        kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia', recipe: recipe
      )
    end
  end

  test 'broadcasts deleted partial for recipe-specific stream on delete' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.broadcast(
        kitchen: @kitchen, action: :deleted, recipe_title: 'Focaccia', recipe: recipe
      )
    end
  end
end
