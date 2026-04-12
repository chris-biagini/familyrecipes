# frozen_string_literal: true

require 'securerandom'

# Short-lived single-use authentication token tied to a User, delivered by
# email (or logged to stdout when SMTP is unconfigured). The code is the
# shared secret between the "check your email" page and the email itself;
# consuming it atomically starts a session. Join-purpose links also carry
# a kitchen_id so consumption can create the matching Membership. Every
# successful consume also opportunistically prunes expired rows — a bridge
# until Solid Queue + a recurring job land (tracked in #384).
#
# - User: the identity the link authenticates as
# - Kitchen: only set when purpose == :join
# - MagicLinkMailer: delivery
# - SessionsController / JoinsController: issue links
# - MagicLinksController: consume links
class MagicLink < ApplicationRecord
  ALPHABET = ('A'..'Z').to_a - %w[I O] + ('2'..'9').to_a
  CODE_LENGTH = 6

  belongs_to :user
  belongs_to :kitchen, optional: true

  enum :purpose, { sign_in: 0, join: 1 }, validate: true, scopes: false

  validates :code, presence: true, uniqueness: true, length: { is: 6 }
  validates :expires_at, presence: true

  before_validation :assign_code, on: :create

  class << self
    def generate_code
      Array.new(CODE_LENGTH) { ALPHABET.sample(random: SecureRandom) }.join
    end

    def consume(raw_code)
      sanitized = normalize(raw_code)
      return nil if sanitized.blank?

      updated = where(code: sanitized, consumed_at: nil)
                .where('expires_at > ?', Time.current)
                .update_all(consumed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- intentional: atomic single-use claim
      return nil unless updated == 1

      cleanup_expired
      find_by(code: sanitized)
    end

    def cleanup_expired
      where('expires_at < ? OR (consumed_at IS NOT NULL AND consumed_at < ?)',
            Time.current, 1.hour.ago).delete_all
    end

    def normalize(raw_code)
      raw_code.to_s.strip.upcase
    end
  end

  private

  def assign_code
    return if code.present?

    self.code = loop do
      candidate = self.class.generate_code
      break candidate unless self.class.exists?(code: candidate)
    end
  end
end
