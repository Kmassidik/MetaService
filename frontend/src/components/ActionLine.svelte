<script lang="ts">
  // The small line next to a control that runs an action: its failure in red, or the success text for a moment. Empty, it takes no room.
  let { line, failed }: { line: string; failed: boolean } = $props()
</script>

<span class="aline" class:bad={failed} class:hide={line === ''} role="status" aria-live="polite">{line}</span>

<style>
  .aline { font-family: var(--mono); font-size: 11px; color: var(--m60); overflow-wrap: anywhere; max-width: 280px; }
  .aline.bad { color: var(--danger); }
  .aline.hide { display: none; }
</style>
