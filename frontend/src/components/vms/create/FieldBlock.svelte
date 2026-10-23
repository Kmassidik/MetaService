<script lang="ts">
  // One row of the Create VM window, as in Proxmox's windows: the label on the left, its control on the right, and the plain lines (captions, notes) the control brings along under it.
  // The window sets rows in two columns; a `wide` row takes both.
  import type { Snippet } from 'svelte'

  interface Props {
    label: string
    /** The id of the control the label names; leave out when the row's control is a custom one that names itself. */
    forId?: string
    /** A small "(optional)" after the label. */
    note?: string | undefined
    /** Gives the label an id so a custom control can be named by it. */
    labelId?: string
    /** Takes the window's whole width instead of one of its two columns. */
    wide?: boolean
    children: Snippet
  }

  let { label, forId, note, labelId, wide = false, children }: Props = $props()
</script>

<div class="block" class:wide>
  <label class="label" id={labelId} for={forId}>{label}{#if note}{' '}<span class="note">{note}</span>{/if}:</label>
  <div class="control">{@render children()}</div>
</div>

<style>
  .block { display: grid; grid-template-columns: var(--label-width, 116px) minmax(0, 1fr); column-gap: 12px; align-items: start; min-width: 0; }
  .block.wide { grid-column: 1 / -1; }
  .label { padding-top: 6px; font: 400 13px/1.4 var(--sans); color: var(--text); }
  .note { color: var(--m50); }
  .control { display: grid; gap: 6px; min-width: 0; }
  @media (max-width: 520px) { .block { --label-width: 92px; column-gap: 10px; } }
</style>
