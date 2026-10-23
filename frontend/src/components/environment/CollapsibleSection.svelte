<script lang="ts">
  // One row of the Environment tab: a full-width header (title, a one-line summary of the current values, a "changed" dot, an "error" badge, a chevron)
  // and the body under it. The body is only hidden when closed, never removed, so what was typed stays in the form.
  import type { Snippet } from 'svelte'

  interface Props {
    /** Short word for the row, used to build the ids that tie the header to its body. */
    id: string
    title: string
    summary: string
    /** A plain sentence at the top of the body. */
    intro?: string
    /** This section has edits that are not saved. */
    changed?: boolean
    /** This section holds a value that cannot be saved. The row opens by itself and stays open while it does. */
    error?: boolean
    open?: boolean
    children: Snippet
  }

  let { id, title, summary, intro = '', changed = false, error = false, open = $bindable(false), children }: Props = $props()

  const headId = $derived(`env-row-${id}-head`)
  const bodyId = $derived(`env-row-${id}-body`)
  const shown = $derived(open || error)

  // Remembered, so the row does not fold shut under the person's hands the moment the last error is fixed.
  $effect(() => { if (error) open = true })

  const toggle = () => { if (!error) open = !open }
</script>

<section class="row" aria-label={title}>
  <h2 class="head">
    <button id={headId} class="trigger" type="button" aria-expanded={shown} aria-controls={bodyId} onclick={toggle}>
      <span class="title">{title}</span>
      <span class="summary">{summary}</span>
      <span class="marks">
        {#if changed}<span class="dot" role="img" aria-label="changed" title="Changed, not saved yet"></span>{/if}
        {#if error}<span class="badge">error</span>{/if}
      </span>
      <svg class="chevron" class:open={shown} viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6" /></svg>
    </button>
  </h2>
  <div id={bodyId} class="body" role="region" aria-labelledby={headId} hidden={!shown}>
    {#if intro}<p class="intro">{intro}</p>{/if}
    {@render children()}
  </div>
</section>

<style>
  .row { border-bottom: 1px solid var(--line); }
  .head { margin: 0; font: inherit; }
  .trigger { display: grid; grid-template-columns: 160px minmax(0, 1fr) auto 14px; align-items: center; column-gap: 16px; width: 100%; min-height: 56px; padding: 10px 4px; border: 0; background: none; color: var(--text); text-align: left; cursor: pointer; }
  .trigger:hover { background: var(--surface-2); }
  .trigger:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: -2px; }
  .title { font: 700 13px var(--mono); letter-spacing: 0.1em; text-transform: uppercase; }
  .summary { font: 12px var(--mono); color: var(--m60); overflow-wrap: anywhere; }
  .marks { display: flex; align-items: center; gap: 8px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent-mark); }
  .badge { padding: 1px 6px; border: 1px solid var(--danger); color: var(--danger); font: 700 10px var(--mono); letter-spacing: 0.08em; text-transform: uppercase; }
  .chevron { color: var(--m50); transition: transform 0.15s; }
  .chevron.open { transform: rotate(180deg); }
  .body { padding: 6px 4px 28px; }
  .intro { margin: 0 0 14px; font-size: 13px; color: var(--m70); }
  @media (max-width: 820px) {
    .trigger { grid-template-columns: minmax(0, 1fr) auto 14px; row-gap: 4px; }
    .summary { grid-column: 1 / -1; grid-row: 2; }
    .marks { grid-column: 2; grid-row: 1; }
    .chevron { grid-column: 3; grid-row: 1; }
  }
</style>
