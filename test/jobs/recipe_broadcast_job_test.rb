# frozen_string_literal: true

require 'test_helper'

class RecipeBroadcastJobTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple bread.

      Category: Bread

      ## Dough

      - Flour, 3 cups

      Mix and knead.
    MD
  end

  test 'broadcast calls RecipeBroadcaster.broadcast with correct args' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    called = false

    RecipeBroadcaster.stub :broadcast, lambda { |kitchen:, action:, recipe_title:, recipe: nil|
      called = true

      assert_equal @kitchen, kitchen
      assert_equal :updated, action
      assert_equal 'Focaccia', recipe_title
      assert_equal recipe.id, recipe&.id
    } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'updated',
        recipe_title: 'Focaccia', recipe_id: recipe.id
      )
    end

    assert called, 'Expected RecipeBroadcaster.broadcast to be called'
  end

  test 'broadcast skips gracefully when recipe not found' do
    called = false

    RecipeBroadcaster.stub :broadcast, ->(**) { called = true } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'created',
        recipe_title: 'Ghost', recipe_id: -1
      )
    end

    assert called, 'Expected broadcast to still fire (recipe: nil for deleted recipes)'
  end

  test 'destroy calls RecipeBroadcaster.broadcast_destroy' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    parent_ids = [42, 99]
    called = false

    RecipeBroadcaster.stub :broadcast_destroy, lambda { |kitchen:, recipe:, recipe_title:, parent_ids:| # rubocop:disable Lint/UnusedBlockArgument
      called = true

      assert_equal @kitchen, kitchen
      assert_equal 'Focaccia', recipe_title
      assert_equal [42, 99], parent_ids
    } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'destroy',
        recipe_title: 'Focaccia', recipe_id: recipe.id,
        parent_ids: parent_ids
      )
    end

    assert called, 'Expected RecipeBroadcaster.broadcast_destroy to be called'
  end
end
