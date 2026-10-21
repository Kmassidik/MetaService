<script lang="ts">
  // One bordered card of the Live tab, in the panel's own card style (.card). Top to bottom: the small label with a "?" for the plain explanation (closed until pressed),
  // the content, and the graph in a strip of fixed height at the bottom so the graphs of a row line up.
  import type { Snippet } from 'svelte'

  let { label, hint = '', children, graph }: { label: string; hint?: string; children: Snippet; graph?: Snippet } = $props()
  let showHint = $state(false)
  const hintId = $props.id()
</script>

<section class="card tile" aria-label={label}>
  <div class="top">
    <h3>{label}</h3>
    {#if hint}
      <button class="iconbtn help" type="button" data-tip="What does this mean?" aria-label="What does {label} mean?" aria-expanded={showHint} aria-controls={hintId} onclick={() => (showHint = !showHint)}>?</button>
    {/if}
  </div>
  {#if showHint}<p class="explain" id={hintId}>{hint}</p>{/if}
  <div class="fill">{@render children()}</div>
  {#if graph}<div class="strip">{@render graph()}</div>{/if}
</section>

<style>
  .tile { padding: 16px; gap: 10px; min-width: 0; }
  .top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .help { width: 22px; height: 22px; padding: 0; font: 700 11px var(--mono); }
  .explain { margin: 0; font-size: 12px; color: var(--m50); }
  .fill { display: grid; gap: 8px; align-content: start; min-width: 0; flex: 1; }
  .strip { display: grid; grid-auto-rows: minmax(0, 1fr); gap: 4px; height: 64px; flex: none; }
</style>
