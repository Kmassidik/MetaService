<script lang="ts">
  // "Harden this machine": folded away, the exact commands of scripts/harden with a Copy button each, and the safety words. Nothing here runs anything.
  import CopyButton from './CopyButton.svelte'
  import { HARDEN_TITLE, SAFETY_LINES, hardenIntro, hardenSteps } from '../../lib/verifySecurity.ts'

  let { os }: { os: string } = $props()
  const steps = $derived(hardenSteps(os))
</script>

<details class="harden" data-testid="harden-box">
  <summary>{HARDEN_TITLE}</summary>
  <ul class="safety">
    {#each SAFETY_LINES as line (line)}<li>{line}</li>{/each}
  </ul>
  <p class="intro">{hardenIntro}</p>
  <ol class="steps">
    {#each steps as step (step.command)}
      <li>
        <span class="what">{step.label}</span>
        <div class="codebox"><code>{step.command}</code><CopyButton text={step.command} describe={step.command} /></div>
      </li>
    {/each}
  </ol>
</details>

<style>
  .harden { margin-top: 10px; font-size: 13px; }
  summary { display: inline-block; padding: 4px 0; font-weight: 600; text-decoration: underline; cursor: pointer; }
  summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
  .safety { margin: 4px 0; padding-left: 18px; color: var(--m70); }
  .intro { margin: 6px 0 4px; color: var(--m70); }
  .steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .what { display: block; color: var(--m70); }
  .codebox { display: flex; gap: 8px; align-items: center; justify-content: space-between; margin-top: 2px; padding: 6px 8px; border: 1px solid var(--line); background: var(--surface); }
  code { min-width: 0; font-family: var(--mono); font-size: 12px; overflow-wrap: anywhere; user-select: all; }
</style>
