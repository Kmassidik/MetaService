<script lang="ts">
  // One topic of the check: a titled card of rows. A card with a blocking cross gets a red outline.
  import CheckRow from './CheckRow.svelte'
  import type { CheckCard } from '../../lib/checkRows.ts'
  import type { ConnectForm, VerifyResult } from '../../lib/types.ts'

  let { card, form, fingerprint, onChecked }: { card: CheckCard; form: ConnectForm; fingerprint: string; onChecked: (result: VerifyResult) => void } = $props()
</script>

<section class="cx-card" class:has-bad={card.hasBlocking} aria-label={card.title}>
  <h4>{card.title}</h4>
  <ul class="checks">
    {#each card.rows as row (row.id)}<CheckRow {row} {form} {fingerprint} {onChecked} />{/each}
  </ul>
</section>

<style>
  .cx-card { padding: 10px 14px 4px; border: 1px solid var(--gray); background: var(--gray2); }
  .cx-card.has-bad { border: 2px solid var(--danger); padding: 9px 13px 3px; }
  h4 { margin: 0 0 4px; font-family: var(--mono); font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--m70); }
  .checks { list-style: none; margin: 0; padding: 0; }
  .checks :global(li + li) { border-top: 1px solid var(--gray); }
</style>
