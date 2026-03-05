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

  test 'notify_recipe_deleted broadcasts to recipe-specific stream' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: 'Focaccia')
    end
  end

  test 'notify_recipe_deleted replaces content with deleted partial and appends toast' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    calls = []
    capture = ->(*args, **kw) { calls << { args:, kw: } }
    append_calls = []
    append_capture = ->(*args, **kw) { append_calls << { args:, kw: } }

    Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
      Turbo::StreamsChannel.stub :broadcast_append_to, append_capture do
        RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: 'Focaccia')
      end
    end

    deleted_call = calls.find { |c| c[:kw][:partial] == 'recipes/deleted' }
    toast_call = append_calls.find { |c| c[:kw][:partial] == 'shared/toast' }

    assert deleted_call, 'Expected recipes/deleted partial'
    assert toast_call, 'Expected toast notification'
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
  end
end
