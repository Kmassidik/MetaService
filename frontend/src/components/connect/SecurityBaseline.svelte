<script lang="ts">
  // The security baseline of the computer, in the Check step: one row per check (ok, warning or unknown) and a plain line each. A warning never stops the install.
  // Everything here came from the other computer through the parent as fixed values; it is drawn as plain text only.
  import HardenBox from './HardenBox.svelte'
  import StatusMark from './StatusMark.svelte'
  import type { MarkKind } from './StatusMark.svelte'
  import { BASELINE_TITLE, INSTALL_ANYWAY, NO_KEY_LINE, lacksKey, verifyRows, warningTotal } from '../../lib/verifySecurity.ts'
  import type { CheckState } from '../../lib/securityRules.ts'
  import type { VerifySecurity } from '../../lib/types.ts'

  let { security, os }: { security: VerifySecurity; os: string } = $props()
  const MARK_OF: Record<CheckState, MarkKind> = { ok: 'ready', warning: 'optional', unknown: 'waiting' }
  const WORD_OF: Record<CheckState, string> = { ok: 'Fine', warning: 'Needs a look', unknown: 'Not known' }
  const rows = $derived(verifyRows(security))
  const warnings = $derived(warningTotal(rows))
</script>

<section class="cx-card sec" aria-label={BASELINE_TITLE} data-warnings={warnings}>
  <h4>{BASELINE_TITLE}</h4>
  <ul class="base">
    {#each rows as row (row.id)}
      <li class="cx-row" data-check={`security-${row.id}`} data-state={row.state}>
        <StatusMark kind={MARK_OF[row.state]} word={WORD_OF[row.state]} />
        <div class="cx-body">
          <div class="lbl">{row.label}</div>
          <div class="det">{row.line}</div>
        </div>
        <span class="val">{row.short}</span>
      </li>
    {/each}
  </ul>
  {#if lacksKey(security)}<p class="nokey" role="alert" data-testid="no-key">{NO_KEY_LINE}</p>{/if}
  <p class="later">{INSTALL_ANYWAY}</p>
  <HardenBox {os} />
</section>

<style>
  .cx-card { padding: 10px 14px 10px; border: 1px solid var(--line); background: var(--surface-2); }
  h4 { margin: 0 0 4px; font-family: var(--mono); font-size: 12px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: var(--m70); }
  .base { list-style: none; margin: 0; padding: 0; }
  .base li + li { border-top: 1px solid var(--line); }
  .cx-row { display: grid; grid-template-columns: 22px minmax(0, 1fr) auto; column-gap: 12px; align-items: start; padding: 8px 0; }
  .cx-row > :global(.mark) { margin-top: 1px; }
  .cx-body { min-width: 0; overflow-wrap: anywhere; }
  .lbl { font-weight: 600; }
  .det { color: var(--m70); font-size: 13px; }
  .val { color: var(--m70); font-size: 13px; text-align: right; padding-top: 1px; }
  .nokey { margin: 8px 0 0; padding: 8px 10px; border: 1px solid var(--danger); border-left-width: 4px; background: var(--surface); color: var(--danger-bright); font-weight: 600; overflow-wrap: anywhere; }
  .later { margin: 8px 0 0; font-size: 13px; color: var(--m70); }
</style>
