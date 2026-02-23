# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def new; end
end
