<script lang="ts">
  // "Show the manual steps": what the parent says to do by hand. The sentence is plain text; only the real commands are in a code box, each with a Copy button.
  import CopyButton from './CopyButton.svelte'
  import type { ManualSteps } from '../../lib/checkRows.ts'

  let { steps }: { steps: ManualSteps } = $props()
</script>

<details class="manual">
  <summary>Show the manual steps</summary>
  <p>{steps.text}</p>
  {#each steps.commands as command (command)}
    <div class="codebox"><code>{command}</code><CopyButton text={command} describe="this command" /></div>
  {/each}
</details>

<style>
  .manual { margin-top: 6px; font-size: 13px; }
  summary { display: inline-block; padding: 4px 0; color: var(--m70); text-decoration: underline; cursor: pointer; }
  summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
  p { margin: 4px 0; color: var(--m70); }
  .codebox { display: flex; gap: 8px; align-items: center; justify-content: space-between; margin-top: 4px; padding: 6px 8px; border: 1px solid var(--line); background: var(--surface); }
  code { min-width: 0; font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; user-select: all; }
</style>
