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
}

if (watch) {
  const ctx = await context(config)
  await ctx.watch()
  console.log("Watching for changes...")
} else {
  await build({ ...config, minify: true })
}
