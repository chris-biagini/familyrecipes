import { build, context } from "esbuild"
import { rmSync, mkdirSync, readdirSync, renameSync, readFileSync, writeFileSync } from "fs"

const watch = process.argv.includes("--watch")

// Clean stale chunk files before each build
rmSync("public/chunks", { recursive: true, force: true })
mkdirSync("public/chunks", { recursive: true })

const config = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  splitting: true,
  format: "esm",
  sourcemap: true,
  outdir: "app/assets/builds",
  publicPath: "/assets",
  chunkNames: "chunks/[name]-[hash]",
  logLevel: "info",
}

// Propshaft fingerprints assets in app/assets/builds/, which breaks
// esbuild's hardcoded chunk URLs. Post-build: move chunks to public/
// (served directly, no fingerprinting) and rewrite import paths.
function rewriteChunkPaths(file) {
  const code = readFileSync(file, "utf8")
  if (code.includes("/assets/chunks/")) {
    writeFileSync(file, code.replaceAll("/assets/chunks/", "/chunks/"))
  }
}

function relocateChunks() {
  const src = "app/assets/builds/chunks"
  try {
    for (const file of readdirSync(src)) {
      renameSync(`${src}/${file}`, `public/chunks/${file}`)
    }
    rmSync(src, { recursive: true, force: true })
  } catch { /* no chunks dir = nothing to move */ }

  rewriteChunkPaths("app/assets/builds/application.js")
  try { rewriteChunkPaths("app/assets/builds/application.js.map") } catch {}

  for (const file of readdirSync("public/chunks")) {
    rewriteChunkPaths(`public/chunks/${file}`)
  }
}

if (watch) {
  // In watch mode, use an onEnd plugin to relocate after each rebuild
  const plugin = {
    name: "relocate-chunks",
    setup(build) {
      build.onEnd(() => relocateChunks())
    }
  }
  const ctx = await context({ ...config, plugins: [plugin] })
  await ctx.watch()
  console.log("Watching for changes...")
} else {
  await build({ ...config, minify: true })
  relocateChunks()
}
