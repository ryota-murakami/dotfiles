import { defineConfig } from 'vitest/config'

// The builder and the controller run in WebKit (the renderer host's web view, the recipient's
// browser): their specs run in a DOM.
export default defineConfig({
  test: {
    environment: 'happy-dom',
    // Not `*.test.ts`: `claude plugin test` takes every such file under the plugin for a hooks test
    include: ['src/**/*.spec.ts'],
  },
})
