import { build, context } from "esbuild"

const watch = process.argv.includes("--watch")

const config = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  sourcemap: true,
  format: "esm",
  outdir: "app/assets/builds",
  publicPath: "/assets",
  logLevel: "info",
  // Mark importmap-only specifiers as external until Task 2 rewrites the JS
  // entry points to use npm-resolvable paths and explicit controller imports.
  external: ["controllers", "controllers/*", "@hotwired/stimulus-loading"],
}

if (watch) {
  const ctx = await context(config)
  await ctx.watch()
  console.log("Watching for changes...")
} else {
  await build({ ...config, minify: true })
}
