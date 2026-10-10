import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// The chat screen is built into the bundle's web folder, which the chat service serves.
export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:9200',
      '/auth': 'http://127.0.0.1:9200',
    },
  },
  build: { outDir: '../web', emptyOutDir: true },
})
