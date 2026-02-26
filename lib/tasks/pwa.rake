# frozen_string_literal: true

namespace :pwa do
  desc 'Generate PWA icons from favicon.svg using rsvg-convert'
  task icons: :environment do
    source = Rails.root.join('app/assets/images/favicon.svg')
    output_dir = Rails.public_path.join('icons')

    abort "Source SVG not found: #{source}" unless source.exist?

    FileUtils.mkdir_p(output_dir)

    icons = {
      'icon-192.png' => 192,
      'icon-512.png' => 512,
      'apple-touch-icon.png' => 180,
      'favicon-32.png' => 32
    }

    icons.each do |filename, size|
      output = output_dir.join(filename)
      system('rsvg-convert', '-w', size.to_s, '-h', size.to_s,
             source.to_s, '-o', output.to_s, exception: true)
      puts "  Generated #{filename} (#{size}x#{size})"
    end
  end
end
