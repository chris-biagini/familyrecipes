# frozen_string_literal: true

require 'test_helper'

class ApplicationControllerTest < ActiveSupport::TestCase
  test 'ApplicationController does not define auto_login_in_development' do
    assert_not ApplicationController.private_method_defined?(:auto_login_in_development, false),
               'auto_login_in_development must not exist — deleted in the auth security audit as a production footgun'
  end

  test 'ApplicationController before_action chain does not reference auto_login_in_development' do
    callback_names = ApplicationController._process_action_callbacks.map(&:filter)

    assert_not_includes callback_names, :auto_login_in_development
  end
end
