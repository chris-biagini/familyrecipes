# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipeBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user

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

  test 'broadcasts meal plan refresh after recipe CRUD' do
    assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
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

  test 'broadcast without recipe skips recipe-specific stream' do
    assert_no_turbo_stream_broadcasts [Recipe.new(id: 0), 'content'] do
      RecipeBroadcaster.broadcast(
        kitchen: @kitchen, action: :deleted, recipe_title: 'Focaccia'
      )
    end
  end

  test 'broadcast_recipe_updated also broadcasts to referencing recipe pages' do
    dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza Dough

      Category: Bread

      ## Mix.
      - Flour, 3 cups
    MD

    _pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # White Pizza

      Category: Bread

      ## Make dough.
      >>> @[Pizza Dough]
    MD

    streams = []
    Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **) { streams << args[0] } do
      RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Pizza Dough', recipe: dough)
    end

    assert streams.any? { |s| s.is_a?(Recipe) && s.slug == 'pizza-dough' },
           'Expected broadcast to pizza-dough recipe stream'
    assert streams.any? { |s| s.is_a?(Recipe) && s.slug == 'white-pizza' },
           'Expected broadcast to white-pizza recipe stream (referencing recipe)'
  end

  test 'notify_recipe_deleted broadcasts to recipe-specific stream' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: 'Focaccia')
    end
  end

  test 'broadcast_destroy notifies recipe page, updates parents, and fires CRUD broadcast' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza Dough

      Category: Bread

      ## Mix.
      - Flour, 3 cups
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # White Pizza

      Category: Bread

      ## Make dough.
      >>> @[Pizza Dough]
    MD

    target_recipe = @kitchen.recipes.find_by!(slug: 'pizza-dough')
    parent_ids = target_recipe.referencing_recipes.pluck(:id)

    calls = []
    capture = ->(*args, **kw) { calls << { args:, kw: } }
    append_calls = []
    append_capture = ->(*args, **kw) { append_calls << { args:, kw: } }

    target_recipe.destroy!

    Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
      Turbo::StreamsChannel.stub :broadcast_append_to, append_capture do
        RecipeBroadcaster.broadcast_destroy(
          kitchen: @kitchen, recipe: target_recipe,
          recipe_title: 'Pizza Dough', parent_ids: parent_ids
        )
      end
    end

    deleted_call = calls.find { |c| c[:kw][:partial] == 'recipes/deleted' }
    parent_call = calls.find { |c| c[:kw][:partial] == 'recipes/recipe_content' && c[:args][0].is_a?(Recipe) }
    listings_call = calls.find { |c| c[:kw][:target] == 'recipe-listings' }
    toast_call = append_calls.find { |c| c[:kw][:partial] == 'shared/toast' }

    assert deleted_call, 'Expected a broadcast with recipes/deleted partial'
    assert parent_call, 'Expected a broadcast updating a parent recipe page'
    assert listings_call, 'Expected a broadcast updating recipe-listings'
    assert toast_call, 'Expected a toast notification'
  end

  test 'broadcast_rename broadcasts redirect to old recipe stream' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    calls = []
    capture = ->(*args, **kw) { calls << { args:, kw: } }
    Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
      RecipeBroadcaster.broadcast_rename(
        recipe, new_title: 'Focaccia Genovese',
                redirect_path: '/recipes/focaccia-genovese'
      )
    end

    assert_equal 1, calls.size
    call = calls.first

    assert_equal recipe, call[:args][0]
    assert_equal 'content', call[:args][1]
    assert_equal 'recipe-content', call[:kw][:target]
    assert_equal 'Focaccia Genovese', call[:kw][:locals][:redirect_title]
    assert_equal '/recipes/focaccia-genovese', call[:kw][:locals][:redirect_path]
    assert_equal 'Focaccia', call[:kw][:locals][:recipe_title]
  end
end
