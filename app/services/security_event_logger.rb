# frozen_string_literal: true

# Narrow audit-log emitter for auth and security events. Every call produces
# a single Rails.logger.info line tagged `[security]` with a JSON payload
# containing the event name, a timestamp, and whatever attributes the caller
# passes. No AR model, no subscribers, no async — just structured lines in
# the same log stream as everything else.
#
# - Called from: SessionsController, MagicLinksController, JoinsController,
#   TransfersController, Authentication concern
# - Read by: whoever greps the production log for `[security]`
class SecurityEventLogger
  def self.log(event, **attrs)
    payload = { event: event, at: Time.current.iso8601, **attrs }
    Rails.logger.tagged('security') { Rails.logger.info(payload.to_json) }
  end
end
