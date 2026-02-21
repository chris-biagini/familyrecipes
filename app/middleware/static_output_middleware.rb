# frozen_string_literal: true

class StaticOutputMiddleware
  def initialize(app, root:, html_fallback: true)
    @app = app
    @root = root.to_s
    @html_fallback = html_fallback
    @file_server = File.directory?(@root) ? Rack::Files.new(@root) : nil
  end

  def call(env)
    return @app.call(env) unless @file_server

    path_info = Rack::Utils.clean_path_info(env[Rack::PATH_INFO])

    return serve(env, path_info) if servable?(path_info)

    if @html_fallback && !path_info.include?('.')
      html_path = "#{path_info}.html"
      return serve(env, html_path) if servable?(html_path)
    end

    index_path = File.join(path_info, 'index.html')
    return serve(env, index_path) if servable?(index_path)

    @app.call(env)
  end

  private

  def servable?(path)
    full = File.join(@root, path)
    File.file?(full) && full.start_with?(@root)
  end

  def serve(env, path)
    env = env.dup
    env[Rack::PATH_INFO] = path
    @file_server.call(env)
  end
end
