# frozen_string_literal: true

# Short-lived single-use authentication token tied to a User, delivered by
# email (or logged to stdout when SMTP is unconfigured). The code is the
# shared secret between the "check your email" page and the email itself;
# consuming it atomically starts a session. Join-purpose links also carry
# a kitchen_id so consumption can create the matching Membership.
#
# - User: the identity the link authenticates as
# - Kitchen: only set when purpose == :join
# - MagicLinkMailer: delivery
# - SessionsController / JoinsController: issue links
# - MagicLinksController: consume links
class MagicLink < ApplicationRecord
  belongs_to :user
  belongs_to :kitchen, optional: true

  enum :purpose, { sign_in: 0, join: 1 }, validate: true, scopes: false

  validates :code, presence: true, uniqueness: true, length: { is: 6 }
  validates :expires_at, presence: true
end
