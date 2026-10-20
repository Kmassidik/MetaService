import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

const CHAT_SERVICE = 'http://127.0.0.1:9200'

// The chat screen is built into the bundle's web folder, which the chat service serves.
export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/api': CHAT_SERVICE,
      '/auth': CHAT_SERVICE,
    },
  },
  build: { outDir: '../web', emptyOutDir: true },
})
