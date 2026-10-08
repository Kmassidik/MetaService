import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// The Root serves ui/dist and the JSON API from one port, so the page calls the API with relative paths.
// In dev, Vite proxies the API paths to a Root running on 9100.
export default defineConfig({
  plugins: [svelte()],
  build: { outDir: 'dist', emptyOutDir: true, assetsInlineLimit: 0, cssCodeSplit: false },
  server: {
    proxy: {
      '/api': 'http://localhost:9100',
      '/auth': 'http://localhost:9100',
      '/health': 'http://localhost:9100',
    },
  },
})
