<script lang="ts">
  // One section of the Create VM window: the small uppercase label over its control, and the plain lines (captions, notes) the control brings along.
  import type { Snippet } from 'svelte'

  interface Props {
    label: string
    /** The id of the control the label names; leave out when the section's control is a custom one that names itself. */
    forId?: string
    /** A small "(optional)" after the label. */
    note?: string
    /** Gives the label an id so a custom control can be named by it. */
    labelId?: string
    children: Snippet
  }

  let { label, forId, note, labelId, children }: Props = $props()
</script>

<div class="block">
  <label class="label" id={labelId} for={forId}>{label}{#if note}{' '}<span class="note">{note}</span>{/if}</label>
  {@render children()}
</div>

<style>
  .block { display: grid; gap: 8px; min-width: 0; }
  .label { font: 700 11px var(--mono); letter-spacing: .14em; text-transform: uppercase; color: var(--m60); }
  .note { font-weight: 400; letter-spacing: 0; text-transform: none; color: var(--m40); }
</style>
