# frozen_string_literal: true

require 'test_helper'
require 'mail'

module Mirepoix
  class LoggerDeliveryTest < ActiveSupport::TestCase
    setup do
      @log = StringIO.new
      @original_logger = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(@log))
    end

    teardown do
      Rails.logger = @original_logger
    end

    test 'deliver! writes to/subject/body to the logger' do
      mail = ::Mail.new do
        to 'alice@test.local'
        from 'no-reply@localhost'
        subject 'Sign in to mirepoix'
        text_part { body "Your code is ABCD23\nExpires in 15 minutes." }
      end

      Mirepoix::LoggerDelivery.new.deliver!(mail)
      output = @log.string

      assert_includes output, 'Mail to: alice@test.local'
      assert_includes output, 'Subject: Sign in to mirepoix'
      assert_includes output, 'ABCD23'
      assert_includes output, 'Expires in 15 minutes'
    end

    test 'deliver! handles plain (non-multipart) mail' do
      mail = ::Mail.new do
        to 'alice@test.local'
        from 'no-reply@localhost'
        subject 'Plain'
        body 'just text'
      end

      Mirepoix::LoggerDelivery.new.deliver!(mail)

      assert_includes @log.string, 'just text'
    end

    test 'registered as :logger Action Mailer delivery method' do
      assert_equal Mirepoix::LoggerDelivery, ActionMailer::Base.delivery_methods[:logger]
    end
  end
end
