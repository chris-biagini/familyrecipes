# frozen_string_literal: true

# Generates light and dark PWA icon PNGs from favicon.svg using rsvg-convert.
# Light icons render from the source SVG directly. Dark icons use a temporary
# SVG with baked-in dark colors because rsvg-convert ignores prefers-color-scheme.
# Output goes to public/icons/ (gitignored). The Dockerfile runs this in its
# builder stage.
module PwaIconGenerator
  SIZES = {
    'icon-192' => 192,
    'icon-512' => 512,
    'apple-touch-icon' => 180,
    'favicon-32' => 32
  }.freeze

  DARK_SVG = <<~SVG
    <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
      <rect width="16" height="16" fill="rgb(38,35,32)" />
      <rect width="8" height="16" fill="rgb(200,55,60)" fill-opacity="0.35" />
      <rect width="16" height="8" fill="rgb(200,55,60)" fill-opacity="0.35" />
    </svg>
  SVG

  def self.generate(source:, output_dir:, suffix: '', &block)
    SIZES.each do |name, size|
      filename = "#{name}#{suffix}.png"
      convert(source: source, output: output_dir.join(filename), size: size)
      block&.call(filename, size)
    end
  end

  def self.convert(source:, output:, size:)
    system('rsvg-convert', '-w', size.to_s, '-h', size.to_s,
           source.to_s, '-o', output.to_s, exception: true)
  end
end

namespace :pwa do
  desc 'Generate light and dark PWA icons from favicon.svg using rsvg-convert'
  task icons: :environment do
    source = Rails.root.join('app/assets/images/favicon.svg')
    output_dir = Rails.public_path.join('icons')

    abort "Source SVG not found: #{source}" unless source.exist?

    FileUtils.mkdir_p(output_dir)

    PwaIconGenerator.generate(source: source, output_dir: output_dir) do |filename, size|
      puts "  Generated #{filename} (#{size}x#{size})"
    end

    Tempfile.create(['favicon-dark', '.svg']) do |dark_svg|
      dark_svg.write(PwaIconGenerator::DARK_SVG)
      dark_svg.flush

      PwaIconGenerator.generate(source: dark_svg.path, output_dir: output_dir, suffix: '-dark') do |filename, size|
        puts "  Generated #{filename} (#{size}x#{size})"
      end
    end
  end
end
