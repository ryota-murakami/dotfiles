import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

import type { Plugin } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'
import { defineConfig } from 'vitest/config'

/** The controller built by vite.controller.config.ts, which runs first (`pnpm build`). */
const CONTROLLER = fileURLToPath(new URL('dist/controller.js', import.meta.url))
const controllerSource = existsSync(CONTROLLER) ? readFileSync(CONTROLLER, 'utf8') : ''

/**
 * Copy DOMPurify's browser build to dist/purify.js: the host injects it into the page view, where
 * page.html's Handout mode sanitizes Markdown output before inserting it (eng D6).
 */
function copyPurify(): Plugin {
  return {
    name: 'dw-handout-copy-purify',
    apply: 'build',
    writeBundle() {
      const source = createRequire(import.meta.url).resolve('dompurify/purify.min.js')
      copyFileSync(source, fileURLToPath(new URL('dist/purify.js', import.meta.url)))
    },
  }
}

// The builder as one self-contained HTML file (dist/builder.html): the host loads it from disk into
// a web view, and the skill runs without Node, so the file is committed.
export default defineConfig({
  plugins: [viteSingleFile(), copyPurify()],
  define: {
    HANDOUT_CONTROLLER_SOURCE: JSON.stringify(controllerSource),
    HANDOUT_CONTROLLER_SHA256: JSON.stringify(createHash('sha256').update(controllerSource).digest('base64')),
  },
  build: {
    target: 'safari15',
    // Committed: keep its bytes stable from build to build
    minify: true,
    sourcemap: false,
    // dist/controller.js was written a moment ago by the controller build
    emptyOutDir: false,
    outDir: 'dist',
    rollupOptions: { input: 'builder.html' },
  },
  test: {
    environment: 'happy-dom',
    // Not `*.test.ts`: `claude plugin test` takes every such file under the plugin for a hooks test
    include: ['src/**/*.spec.ts'],
  },
})
