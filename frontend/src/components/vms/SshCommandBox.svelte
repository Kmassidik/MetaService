<script lang="ts">
  // The ssh command to paste in a terminal, in a box with a Copy button. The command wraps, so a long one never scrolls the page sideways.
  import CopyAddress from './CopyAddress.svelte'

  let { command, subject }: { command: string; subject: string } = $props()
</script>

<div class="box"><code>{command}</code><CopyAddress address={command} label="Copy command" {subject} /></div>

<style>
  .box { display: flex; align-items: stretch; gap: 8px; border: 1px solid var(--line); padding: 8px; background: var(--surface-2); }
  code { flex: 1; min-width: 0; font-family: var(--mono); font-size: 12.5px; background: none; padding: 4px 2px; overflow-wrap: anywhere; align-self: center; }
</style>
