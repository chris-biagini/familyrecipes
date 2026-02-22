# frozen_string_literal: true

# Test helper - loads the library and sets up test environment

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'minitest/autorun'
