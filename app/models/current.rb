# frozen_string_literal: true

# Request-scoped global state via ActiveSupport::CurrentAttributes. Holds the
# current Session (and delegates #user). Set by the Authentication concern on
# each request; consumed by controllers and views via Current.user.
#
# Also holds batching_kitchen — set by Kitchen.batch_writes to defer
# reconciliation and broadcasts until the batch block completes.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :batching_kitchen

  delegate :user, to: :session, allow_nil: true
end
