<script lang="ts">
  // The layout the form sections share: fields side by side on a wide screen, one under the other on a phone.
  import type { Snippet } from 'svelte'

  let { children }: { children: Snippet } = $props()
</script>

<div class="cols">{@render children()}</div>

<style>
  .cols { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 16px; align-items: start; }
</style>
