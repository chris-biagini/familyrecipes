# frozen_string_literal: true

require 'minitest/autorun'
require 'rack'
require 'fileutils'
require 'tmpdir'

require_relative '../../app/middleware/static_output_middleware'

class StaticOutputMiddlewareTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, 'style.css'), 'body { color: red; }')
    File.write(File.join(@dir, 'pizza-dough.html'), '<h1>Pizza Dough</h1>')
    File.write(File.join(@dir, '404.html'), '<h1>Not Found</h1>')
    FileUtils.mkdir_p(File.join(@dir, 'index'))
    File.write(File.join(@dir, 'index', 'index.html'), '<h1>Ingredient Index</h1>')

    @inner_app = ->(_env) { [404, { 'content-type' => 'text/plain' }, ['Not Found']] }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_serves_exact_file
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, headers, = middleware.call(env_for('/style.css'))

    assert_equal 200, status
    assert_match %r{text/css}, headers['content-type']
  end

  def test_serves_html_via_clean_url
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/pizza-dough'))

    assert_equal 200, status
  end

  def test_serves_directory_index
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/index/'))

    assert_equal 200, status
  end

  def test_falls_through_for_unknown_path
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/nonexistent'))

    assert_equal 404, status
  end

  def test_html_fallback_disabled_skips_clean_urls
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/pizza-dough'))

    assert_equal 404, status
  end

  def test_html_fallback_disabled_still_serves_exact_files
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/style.css'))

    assert_equal 200, status
  end

  def test_html_fallback_disabled_still_serves_directory_index
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir, html_fallback: false)
    status, = middleware.call(env_for('/index/'))

    assert_equal 200, status
  end

  def test_gracefully_handles_missing_root_directory
    middleware = StaticOutputMiddleware.new(@inner_app, root: '/nonexistent/path')
    status, = middleware.call(env_for('/style.css'))

    assert_equal 404, status
  end

  def test_prevents_path_traversal
    middleware = StaticOutputMiddleware.new(@inner_app, root: @dir)
    status, = middleware.call(env_for('/../../../etc/passwd'))

    assert_equal 404, status
  end

  private

  def env_for(path)
    Rack::MockRequest.env_for(path)
  end
end
