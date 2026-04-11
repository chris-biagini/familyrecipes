# frozen_string_literal: true

# Action Mailer delivery method that writes the full email to Rails.logger
# instead of handing it to an SMTP server. Registered as `:logger` in
# config/application.rb and selected by production/development env files
# when no SMTP configuration is present.
#
# The primary use case is a self-hosted deployment without outbound email:
# the operator runs `docker logs <container>` and reads the 6-character
# magic link code directly from stdout. Mirrors Fizzy's fallback pattern
# (see docs/docker-deployment.md in basecamp/fizzy).
#
# - ActionMailer::Base.delivery_method = :logger selects this
# - Rails.logger: receives the rendered mail
module FamilyRecipes
  class LoggerDelivery
    def initialize(_settings = nil); end

    def deliver!(mail)
      separator = '-' * 60
      lines = [
        separator,
        "Mail to: #{Array(mail.to).join(', ')}",
        "Subject: #{mail.subject}",
        '',
        text_body(mail),
        separator
      ]
      Rails.logger.info(lines.join("\n"))
    end

    private

    def text_body(mail)
      part = mail.text_part || (mail.multipart? ? nil : mail)
      return '(no text part)' unless part

      part.body.to_s
    end
  end
end
