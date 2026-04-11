#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Import prompt evaluation runner. Standalone script — no Rails boot.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb [iteration_label]
#   ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb --corpus=corpus_v2 [label]
#
# Runs each test corpus recipe through:
#   1. Haiku generation (using current prompt_template.md)
#   2. Layer 1: parse check (structural validity)
#   3. Layer 2: format check (formatting rules)
#   4. Layer 3: Sonnet fidelity judge (content preservation)
#
# Results saved to test/ai_import/results/iteration_NNN/

require 'json'
require 'fileutils'

# ActiveSupport polyfill — parser uses .presence in a few spots
class Object
  def presence
    self if respond_to?(:empty?) ? !empty? : !nil?
  end
end

# Load parser pipeline
require_relative '../../lib/mirepoix'
require_relative 'scorers/parse_checker'
require_relative 'scorers/format_checker'

# Anthropic SDK
require 'anthropic'

BASE_DIR = File.expand_path(__dir__)
RESULTS_DIR = File.join(BASE_DIR, 'results')

GENERATION_MODEL = 'claude-sonnet-4-6'
JUDGE_MODEL = 'claude-sonnet-4-6'

CATEGORIES = %w[Baking Bread Breakfast Dessert Drinks Holiday Mains Pizza Sides Snacks Miscellaneous].freeze

TAGS = %w[vegetarian vegan gluten-free weeknight easy quick one-pot make-ahead
          freezer-friendly grilled roasted baked comfort-food holiday american
          italian mexican french japanese chinese indian thai].freeze

def parse_args
  corpus_name = 'corpus'
  prompt_name = 'prompt_template.md'
  label = nil

  ARGV.each do |arg|
    if arg.start_with?('--corpus=')
      corpus_name = arg.delete_prefix('--corpus=')
    elsif arg.start_with?('--prompt=')
      prompt_name = arg.delete_prefix('--prompt=')
    else
      label = arg
    end
  end

  [File.join(BASE_DIR, corpus_name), File.join(BASE_DIR, prompt_name), label]
end

def load_prompt_template(prompt_path)
  template = File.read(prompt_path)
  template.gsub('{{CATEGORIES}}', CATEGORIES.join(', '))
          .gsub('{{TAGS}}', TAGS.join(', '))
end

def corpus_dirs(corpus_dir)
  Dir.glob(File.join(corpus_dir, '*')).select { |f| File.directory?(f) }.sort
end

def call_haiku(client, system_prompt, input_text)
  response = client.messages.create(
    model: GENERATION_MODEL,
    max_tokens: 8192,
    system: system_prompt,
    messages: [{ role: 'user', content: input_text }]
  )
  text = response.content.find { |block| block.type == :text }&.text || ''
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  heading_index = text.index(/^# /)
  heading_index ? text[heading_index..] : text
end

def call_sonnet_judge(client, judge_prompt, original, output, expected)
  user_content = if expected
                   "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}\n\n## REFERENCE\n\n#{expected}"
                 else
                   "## ORIGINAL\n\n#{original}\n\n## OUTPUT\n\n#{output}"
                 end

  response = client.messages.create(
    model: JUDGE_MODEL,
    max_tokens: 4096,
    system: judge_prompt,
    messages: [{ role: 'user', content: user_content }]
  )
  text = response.content.find { |block| block.type == :text }&.text || '{}'
  text = text.gsub(/\A```\w*\n/, '').delete_suffix("\n```").strip
  JSON.parse(text)
rescue JSON::ParserError => error
  { 'error' => "JSON parse failed: #{error.message}", 'fidelity_score' => 0, 'detritus_score' => 0 }
end

def expected_ingredient_count(expected_text)
  return nil unless expected_text

  tokens = LineClassifier.classify(expected_text)
  parsed = RecipeBuilder.new(tokens).build
  parsed[:steps].sum { |s| (s[:ingredients] || []).size }
rescue Mirepoix::ParseError
  nil
end

def compute_aggregate(parse_result, format_result, fidelity_result)
  return 0.0 unless parse_result.pass

  fidelity = (fidelity_result['fidelity_score'] || 0).to_f
  detritus = (fidelity_result['detritus_score'] || 0).to_f
  format_score = format_result.score * 100.0

  (0.3 * format_score) + (0.4 * fidelity) + (0.3 * detritus)
end

def write_summary(iter_dir, scores, output_dir)
  lines = ["# Iteration #{File.basename(iter_dir)}\n"]
  lines << '| Recipe | Parse | Format | Fidelity | Detritus | Aggregate |'
  lines << '|--------|-------|--------|----------|----------|-----------|'

  scores.each do |name, data|
    parse = data[:parse][:pass] ? 'PASS' : 'FAIL'
    format_s = "#{data[:format][:score]}%"
    fidelity = data[:fidelity]['fidelity_score'] || 0
    detritus = data[:fidelity]['detritus_score'] || 0
    agg = data[:aggregate]
    lines << "| #{name} | #{parse} | #{format_s} | #{fidelity} | #{detritus} | #{agg} |"
  end

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size).round(1)
  worst = scores.values.map { |s| s[:aggregate] } # rubocop:disable Rails/Pluck -- no Rails.min.round(1)
  lines << ''
  lines << "**Overall:** #{avg} avg, #{worst} worst"
  lines << ''

  append_failure_details(lines, scores, output_dir)

  File.write(File.join(iter_dir, 'summary.md'), lines.join("\n"))
end

def append_failure_details(lines, scores, output_dir)
  fidelity_keys = %w[ingredients_missing ingredients_added quantities_changed instructions_dropped
                     instructions_rewritten detritus_retained prep_leaked_into_name]
  scores.each do |name, data|
    failures = []
    failures << "PARSE FAILED: #{data[:parse][:details][:errors].join(', ')}" unless data[:parse][:pass]
    data[:format][:checks].each do |check|
      next if check[:pass]

      detail = check[:failures] ? " — #{check[:failures].join(', ')}" : ''
      failures << "FORMAT: #{check[:name]}#{detail}"
    end
    fidelity_keys.each do |key|
      items = data[:fidelity][key]
      next if items.nil? || items.empty? # rubocop:disable Rails/Blank -- no Rails in standalone script

      failures << "FIDELITY: #{key}: #{items.join(', ')}"
    end

    next if failures.empty?

    lines << "### #{name} — issues"
    failures.each { |f| lines << "- #{f}" }

    if data[:aggregate] < 90
      output_file = File.join(output_dir, "#{name}.md")
      if File.exist?(output_file)
        snippet = File.readlines(output_file).first(20).join
        lines << ''
        lines << '**Output snippet (first 20 lines):**'
        lines << '```'
        lines << snippet
        lines << '```'
      end
    end

    lines << ''
  end
end

def run_evaluation
  api_key = ENV.fetch('ANTHROPIC_API_KEY') { abort 'Set ANTHROPIC_API_KEY environment variable' }
  client = Anthropic::Client.new(api_key: api_key, timeout: 90)

  corpus_dir, prompt_path, label = parse_args
  puts "Corpus: #{corpus_dir}"
  puts "Prompt: #{prompt_path}"

  system_prompt = load_prompt_template(prompt_path)
  judge_prompt = File.read(File.join(BASE_DIR, 'scorers', 'fidelity_judge_prompt.md'))

  unless label
    existing = Dir.glob(File.join(RESULTS_DIR, 'iteration_*'))
                  .map { |d| File.basename(d).delete_prefix('iteration_').to_i }
    label = format('%03d', (existing.max || 0) + 1)
  end
  iter_dir = File.join(RESULTS_DIR, "iteration_#{label}")
  output_dir = File.join(iter_dir, 'outputs')
  FileUtils.mkdir_p(output_dir)

  scores = {}
  dirs = corpus_dirs(corpus_dir)

  dirs.each_with_index do |dir, idx|
    name = File.basename(dir)
    input_text = File.read(File.join(dir, 'input.txt'))
    expected_path = File.join(dir, 'expected.md')
    expected_text = File.exist?(expected_path) ? File.read(expected_path) : nil

    puts "[#{idx + 1}/#{dirs.size}] #{name}: calling #{GENERATION_MODEL}..."
    output_text = call_haiku(client, system_prompt, input_text)
    File.write(File.join(output_dir, "#{name}.md"), output_text)

    puts '  Layer 1: parse check...'
    exp_count = expected_ingredient_count(expected_text)
    parse_result = Scorers::ParseChecker.check(output_text, expected_ingredient_count: exp_count)

    puts '  Layer 2: format check...'
    format_result = Scorers::FormatChecker.check(output_text, valid_categories: CATEGORIES, input_text: input_text)

    puts '  Layer 3: Sonnet fidelity judge...'
    fidelity_result = call_sonnet_judge(client, judge_prompt, input_text, output_text, expected_text)

    aggregate = compute_aggregate(parse_result, format_result, fidelity_result)

    scores[name] = {
      parse: { pass: parse_result.pass, details: parse_result.details },
      format: { score: (format_result.score * 100).round(1), checks: format_result.checks },
      fidelity: fidelity_result,
      aggregate: aggregate.round(1)
    }

    puts "  Aggregate: #{aggregate.round(1)}"
  end

  File.write(File.join(iter_dir, 'scores.json'), JSON.pretty_generate(scores))
  write_summary(iter_dir, scores, output_dir)

  avg = (scores.values.sum { |s| s[:aggregate] } / scores.size).round(1)
  worst = scores.values.map { |s| s[:aggregate] } # rubocop:disable Rails/Pluck -- no Rails.min.round(1)
  puts "\nResults saved to #{iter_dir}/"
  puts "Overall: #{avg} avg, #{worst} worst"
end

run_evaluation if $PROGRAM_NAME == __FILE__
