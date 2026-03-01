# frozen_string_literal: true

# Request-scoped global state via ActiveSupport::CurrentAttributes. Holds the
# current Session (and delegates #user). Set by the Authentication concern on
# each request; consumed by controllers and views via Current.user.
class Current < ActiveSupport::CurrentAttributes
  attribute :session

  delegate :user, to: :session, allow_nil: true
end
