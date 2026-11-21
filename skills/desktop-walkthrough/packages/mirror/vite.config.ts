import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'
import { defineConfig } from 'vitest/config'

// One self-contained HTML file: the HUD loads it from disk into a web view, where a page may not
// fetch sibling files. `scripts/dw` copies `dist/index.html` beside the HUD's other pages.
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: {
    target: 'safari17',
    // The file is committed (the skill runs without Node): keep its bytes stable from build to build
    minify: true,
    sourcemap: false,
    emptyOutDir: true,
  },
  test: {
    environment: 'happy-dom',
    // The theme spec reads theme.css as text; by default the runner blanks stylesheets
    css: true,
    setupFiles: ['src/test-setup.ts'],
    // Not `*.test.ts`: `claude plugin test` takes every such file under the plugin for a hooks test
    include: ['src/**/*.spec.{ts,tsx}'],
  },
})
