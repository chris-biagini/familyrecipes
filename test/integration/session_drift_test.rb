# frozen_string_literal: true

require 'test_helper'

class SessionDriftTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'resume_session logs :session_drift when UA differs from stored session' do
    log_in
    session = Session.last
    session.update!(user_agent: 'original-agent/1.0')

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: { 'User-Agent' => 'different-agent/2.0' }
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_response :success
    assert_match(/\[security\].*"event":"session_drift"/, io.string)
  end

  test 'resume_session does NOT log drift when UA matches' do
    log_in
    session = Session.last

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      get kitchen_root_path(kitchen_slug: @kitchen.slug), headers: { 'User-Agent' => session.user_agent }
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_no_match(/session_drift/, io.string)
  end

  test 'start_new_session_for logs :session_created' do
    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      log_in
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_match(/\[security\].*"event":"session_created"/, io.string)
  end

  test 'terminate_session logs :session_destroyed' do
    log_in

    io = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    begin
      delete logout_path
    ensure
      Rails.logger = Rails.application.config.logger || Rails.logger
    end

    assert_match(/\[security\].*"event":"session_destroyed"/, io.string)
  end
end
