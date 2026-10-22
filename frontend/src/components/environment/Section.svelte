<script lang="ts">
  // One block of the Environment tab: a small heading, an optional plain sentence under it, and the content.
  import type { Snippet } from 'svelte'

  let { title, intro = '', children }: { title: string; intro?: string; children: Snippet } = $props()
</script>

<section class="block" aria-label={title}>
  <h2 class="subhead">{title}</h2>
  {#if intro}<p class="intro">{intro}</p>{/if}
  {@render children()}
</section>

<style>
  .block { margin-bottom: 32px; }
  .subhead { margin: 0 0 10px; font: 700 13px var(--mono); letter-spacing: 0.1em; text-transform: uppercase; }
  .intro { margin: 0 0 14px; font-size: 13px; color: var(--m70); }
</style>
