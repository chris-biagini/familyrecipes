# frozen_string_literal: true

require 'test_helper'

class SecurityEventLoggerTest < ActiveSupport::TestCase
  setup do
    @io = StringIO.new
    @original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(@io))
  end

  teardown do
    Rails.logger = @original_logger
  end

  test 'log emits a tagged JSON line containing the event name' do
    SecurityEventLogger.log(:magic_link_issued, user_id: 42, purpose: :sign_in)

    output = @io.string

    assert_includes output, '[security]'
    assert_match(/"event":"magic_link_issued"/, output)
    assert_match(/"user_id":42/, output)
    assert_match(/"purpose":"sign_in"/, output)
  end

  test 'log includes an ISO8601 timestamp' do
    SecurityEventLogger.log(:session_created)

    output = @io.string

    assert_match(/"at":"\d{4}-\d{2}-\d{2}T/, output)
  end

  test 'log handles events with no attributes' do
    assert_nothing_raised do
      SecurityEventLogger.log(:session_destroyed)
    end

    assert_match(/"event":"session_destroyed"/, @io.string)
  end

  test 'log emits exactly one line per call' do
    SecurityEventLogger.log(:magic_link_issued, user_id: 1)

    assert_equal 1, @io.string.lines.size
  end
end
