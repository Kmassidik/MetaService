<script lang="ts">
  // A labelled row of option cards: the small uppercase label over a radio group. The cards are given by the caller.
  import type { Snippet } from 'svelte'

  interface Props {
    /** The label above the cards; also the group's accessible name. */
    label: string
    /** The cards per row on a wide screen; a phone gets fewer (see the styles). */
    columns: 2 | 3 | 4
    children: Snippet
  }

  let { label, columns, children }: Props = $props()
  const labelId = $props.id()
</script>

<section class="group">
  <h4 class="label" id={labelId}>{label}</h4>
  <div class="cards c{columns}" role="radiogroup" aria-labelledby={labelId}>{@render children()}</div>
</section>

<style>
  .group { display: grid; gap: 8px; min-width: 0; }
  .label { margin: 0; font: 700 10px var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--m50); }
  .cards { display: grid; gap: 8px; }
  .c2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .c3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .c4 { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  @media (max-width: 520px) {
    .c3 { grid-template-columns: minmax(0, 1fr); }
    .c4 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  }
</style>
