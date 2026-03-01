# frozen_string_literal: true

class AllowNullStepTitle < ActiveRecord::Migration[8.1]
  def change
    change_column_null :steps, :title, true
  end
end
