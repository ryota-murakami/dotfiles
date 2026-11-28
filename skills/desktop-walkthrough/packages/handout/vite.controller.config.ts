import { defineConfig } from 'vite'

// The Handout's controller as one classic script: the builder inlines dist/controller.js into every
// Handout and its CSP allows it by hash. Built before the builder (see vite.config.ts), which reads it.
export default defineConfig({
  build: {
    target: 'safari15',
    // Committed and hashed into every Handout's CSP: keep its bytes stable from build to build
    minify: true,
    sourcemap: false,
    emptyOutDir: false,
    outDir: 'dist',
    lib: {
      entry: 'src/controller/entry.ts',
      formats: ['iife'],
      name: 'dwHandoutController',
      fileName: () => 'controller.js',
    },
  },
})
