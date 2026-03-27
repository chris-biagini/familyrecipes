# frozen_string_literal: true

require 'test_helper'

class CurrentResolverCacheTest < ActiveSupport::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user
    Current.reset
  end

  teardown { Current.reset }

  test 'resolver_for reuses cached lookup within a request' do
    first = IngredientCatalog.resolver_for(@kitchen)
    second = IngredientCatalog.resolver_for(@kitchen)

    assert_same first.lookup, second.lookup
  end

  test 'resolver_for rebuilds lookup after Current.reset' do
    first = IngredientCatalog.resolver_for(@kitchen)
    Current.reset
    second = IngredientCatalog.resolver_for(@kitchen)

    assert_not_same first.lookup, second.lookup
  end

  test 'resolver_for issues no queries on second call' do
    IngredientCatalog.resolver_for(@kitchen)

    count = 0
    counter = lambda { |_name, _start, _finish, _id, payload|
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      IngredientCatalog.resolver_for(@kitchen)
    end

    assert_equal 0, count, 'Second call should use cached lookup'
  end
end
