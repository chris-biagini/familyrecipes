# frozen_string_literal: true

# Base class for all mailers in the app. Currently the only mailer is
# MagicLinkMailer; other transactional mail can subclass this. Delivery
# transport is configured per-environment (see config/environments/*).
class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch('MAILER_FROM_ADDRESS', 'no-reply@localhost') }
  layout 'mailer'
end
