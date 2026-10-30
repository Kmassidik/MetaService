<script lang="ts">
  // A line to paste somewhere, in a box with a Copy button. Long lines wrap, so the page never scrolls sideways.
  import CopyButton from '../connect/CopyButton.svelte'

  let { text, describe }: { text: string; describe: string } = $props()
</script>

<div class="box"><pre data-testid="code-{describe.replaceAll(' ', '-')}">{text}</pre><CopyButton {text} {describe} /></div>

<style>
  .box { display: flex; align-items: flex-start; gap: 8px; border: 1px solid var(--line); padding: 8px; background: var(--surface-2); }
  pre { flex: 1; min-width: 0; margin: 0; padding: 4px 2px; font-family: var(--mono); font-size: 12.5px; white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
