<script>
  import { stepText } from '../../../lib/runSteps.js'

  // What the bot did, one plain line per step, joined by a thin timeline.
  let { steps = [], id = '' } = $props()
</script>

<ol class="steps" {id} aria-label="Steps">
  {#each steps as step (step.id)}
    <li>{stepText(step)}</li>
  {/each}
</ol>

<style>
  .steps { --dot: 7px; margin: 4px 0 2px; padding: 0; list-style: none; color: var(--text-2); font: 400 var(--fs-preview)/1.45 var(--font); }
  li { position: relative; padding: 4px 0 4px 20px; overflow-wrap: anywhere; }
  /* Dot centred on the first text line; the line runs down to the next dot. */
  li::before {
    content: ''; position: absolute; left: 3px; top: calc(4px + .725em - var(--dot) / 2);
    width: var(--dot); height: var(--dot); border-radius: var(--radius-pill); background: var(--text-3);
  }
  li:not(:last-child)::after {
    content: ''; position: absolute; left: calc(3px + var(--dot) / 2 - .5px); top: calc(4px + .725em + var(--dot) / 2 + 2px); bottom: calc(-4px - .725em + var(--dot) / 2 + 2px);
    width: 1px; background: var(--hairline);
  }
</style>
