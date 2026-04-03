#!/usr/bin/env ruby
# frozen_string_literal: true

# Hallucination comparison: runs the same prompt through both Haiku and Sonnet
# on deliberately incomplete/vague recipe inputs.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... ruby test/ai_import/hallucination_test.rb

require 'json'
require 'fileutils'

BASE_DIR = File.expand_path(__dir__)
CORPUS_DIR = File.join(BASE_DIR, 'corpus_hallucination')
OUTPUT_DIR = File.join(BASE_DIR, 'results', 'hallucination_comparison')

HAIKU_MODEL = 'claude-haiku-4-5-20251001'
SONNET_MODEL = 'claude-sonnet-4-6'

CATEGORIES = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous].freeze

require 'anthropic'

def load_prompt
  template = File.read(File.join(BASE_DIR, 'prompt_template.md'))
  template.gsub('{{CATEGORIES}}', CATEGORIES.join(', '))
end

def call_model(client, model, system_prompt, input_text)
  response = client.messages.create(
    model: model,
    max_tokens: 8192,
    system: system_prompt,
    messages: [{ role: 'user', content: input_text }]
  )
  text = response.content.find { |block| block.type == :text }&.text || ''
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? text[heading_index..] : text
end

def run_comparison
  api_key = ENV.fetch('ANTHROPIC_API_KEY') { abort 'Set ANTHROPIC_API_KEY environment variable' }
  client = Anthropic::Client.new(api_key: api_key, timeout: 90)
  system_prompt = load_prompt

  FileUtils.mkdir_p(OUTPUT_DIR)

  dirs = Dir.glob(File.join(CORPUS_DIR, '*')).select { |f| File.directory?(f) }.sort

  dirs.each_with_index do |dir, idx|
    name = File.basename(dir)
    input_text = File.read(File.join(dir, 'input.txt'))

    puts "=== [#{idx + 1}/#{dirs.size}] #{name} ==="
    puts

    puts '  Haiku...'
    haiku_output = call_model(client, HAIKU_MODEL, system_prompt, input_text)
    File.write(File.join(OUTPUT_DIR, "#{name}_haiku.md"), haiku_output)

    puts '  Sonnet...'
    sonnet_output = call_model(client, SONNET_MODEL, system_prompt, input_text)
    File.write(File.join(OUTPUT_DIR, "#{name}_sonnet.md"), sonnet_output)

    puts
    puts '  --- INPUT (first 10 lines) ---'
    input_text.lines.first(10).each { |l| puts "  #{l}" }
    puts
    puts '  --- HAIKU OUTPUT ---'
    haiku_output.lines.each { |l| puts "  #{l}" }
    puts
    puts '  --- SONNET OUTPUT ---'
    sonnet_output.lines.each { |l| puts "  #{l}" }
    puts
    puts '=' * 60
    puts
  end
end

run_comparison if $PROGRAM_NAME == __FILE__
