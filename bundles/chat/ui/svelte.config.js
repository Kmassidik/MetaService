import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

// Lets Svelte (and svelte-check) read <script lang="ts"> in the components.
export default { preprocess: vitePreprocess() }
