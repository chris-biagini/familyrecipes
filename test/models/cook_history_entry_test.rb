# frozen_string_literal: true

require 'test_helper'

class CookHistoryEntryTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    CookHistoryEntry.delete_all
  end

  test 'acts_as_tenant scopes to current kitchen' do
    CookHistoryEntry.record(kitchen: @kitchen, recipe_slug: 'pasta')

    with_multi_kitchen do
      other = ActsAsTenant.without_tenant do
        Kitchen.create!(name: 'Other', slug: 'other')
      end
      ActsAsTenant.with_tenant(other) do
        CookHistoryEntry.record(kitchen: other, recipe_slug: 'soup')
      end
    end

    assert_equal 1, CookHistoryEntry.where(recipe_slug: 'pasta').size
    assert_equal 0, CookHistoryEntry.where(recipe_slug: 'soup').size
  end

  test 'record creates entry with cooked_at near current time' do
    freeze_time do
      entry = CookHistoryEntry.record(kitchen: @kitchen, recipe_slug: 'bagels')

      assert entry.persisted?
      assert_equal 'bagels', entry.recipe_slug
      assert_equal @kitchen.id, entry.kitchen_id
      assert_in_delta Time.current, entry.cooked_at, 1.second
    end
  end

  test 'record creates multiple entries for the same slug' do
    CookHistoryEntry.record(kitchen: @kitchen, recipe_slug: 'tacos')
    CookHistoryEntry.record(kitchen: @kitchen, recipe_slug: 'tacos')

    assert_equal 2, CookHistoryEntry.where(recipe_slug: 'tacos').size
  end

  test 'recent scope returns entries within WINDOW days' do
    freeze_time do
      recent = CookHistoryEntry.create!(recipe_slug: 'new', cooked_at: 10.days.ago)
      CookHistoryEntry.create!(recipe_slug: 'old', cooked_at: 91.days.ago)

      results = CookHistoryEntry.recent

      assert_includes results, recent
      assert_equal 1, results.size
    end
  end

  test 'recent scope excludes entries exactly at the boundary' do
    freeze_time do
      CookHistoryEntry.create!(recipe_slug: 'boundary', cooked_at: 90.days.ago)

      assert_empty CookHistoryEntry.recent
    end
  end

  test 'prune! deletes entries older than WINDOW' do
    freeze_time do
      CookHistoryEntry.create!(recipe_slug: 'keep', cooked_at: 30.days.ago)
      CookHistoryEntry.create!(recipe_slug: 'remove', cooked_at: 100.days.ago)

      CookHistoryEntry.prune!(kitchen: @kitchen)

      assert_equal 1, CookHistoryEntry.count
      assert_equal 'keep', CookHistoryEntry.first.recipe_slug
    end
  end

  test 'prune! only deletes entries for the given kitchen' do
    with_multi_kitchen do
      other = ActsAsTenant.without_tenant do
        Kitchen.create!(name: 'Other', slug: 'other')
      end

      freeze_time do
        CookHistoryEntry.create!(recipe_slug: 'ours-old', cooked_at: 100.days.ago)

        ActsAsTenant.with_tenant(other) do
          CookHistoryEntry.create!(recipe_slug: 'theirs-old', cooked_at: 100.days.ago)
        end

        CookHistoryEntry.prune!(kitchen: @kitchen)

        assert_equal 0, CookHistoryEntry.count
        ActsAsTenant.with_tenant(other) do
          assert_equal 1, CookHistoryEntry.count
        end
      end
    end
  end

  test 'WINDOW is 90 days' do
    assert_equal 90, CookHistoryEntry::WINDOW
  end
end
