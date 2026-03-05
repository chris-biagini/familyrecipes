# frozen_string_literal: true

require 'test_helper'
require 'rake'

class PwaIconsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('pwa:icons')
    Rake::Task['pwa:icons'].reenable
  end

  test 'generates light and dark icon PNGs' do
    skip 'rsvg-convert not installed' unless system('which rsvg-convert > /dev/null 2>&1')

    Rake::Task['pwa:icons'].invoke

    icons_dir = Rails.public_path.join('icons')
    expected = %w[
      icon-192.png icon-512.png apple-touch-icon.png favicon-32.png
      icon-192-dark.png icon-512-dark.png apple-touch-icon-dark.png favicon-32-dark.png
    ]

    expected.each do |filename|
      path = icons_dir.join(filename)
      assert path.exist?, "Expected #{filename} to be generated"
      assert path.size.positive?, "Expected #{filename} to be non-empty"
    end
  end
end
