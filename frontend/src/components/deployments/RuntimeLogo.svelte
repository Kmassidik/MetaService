<script lang="ts">
  // A runtime's logo (Docker today) as a small picture; nothing is drawn for a runtime that has none.
  import { LOGOS, type LogoName } from '../../lib/logos.ts'

  let { logo, size = 18 }: { logo: LogoName | null; size?: number } = $props()
</script>

{#if logo}<img class="runtime-logo" src={LOGOS[logo]} alt="" width={size} height={size} />{/if}

<style>
  .runtime-logo { flex: none; vertical-align: middle; }
</style>
