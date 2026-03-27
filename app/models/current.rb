# frozen_string_literal: true

# Request-scoped global state via ActiveSupport::CurrentAttributes. Holds the
# current Session (and delegates #user). Set by the Authentication concern on
# each request; consumed by controllers and views via Current.user.
#
# Also holds batching_kitchen — set by Kitchen.batch_writes to defer
# reconciliation and broadcasts until the batch block completes.
# broadcast_pending — set by Kitchen.run_finalization, flushed by
# ApplicationController's after_action to defer broadcasts until after
# the response transaction completes.
# resolver_lookup — cached IngredientCatalog lookup hash, built once per
# request by IngredientCatalog.resolver_for to avoid repeated DB queries
# and variant-hash construction. Each resolver_for call wraps the cached
# lookup in a fresh IngredientResolver (which carries mutable state).
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :batching_kitchen, :broadcast_pending, :resolver_lookup

  delegate :user, to: :session, allow_nil: true
end
