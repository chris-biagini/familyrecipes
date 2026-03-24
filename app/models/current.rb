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
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :batching_kitchen, :broadcast_pending

  delegate :user, to: :session, allow_nil: true
end
