<script lang="ts">
  // One requirement as a row of a fixed grid: mark | text | value or action. A tick is one short line; a cross is one plain sentence, the action, and the manual steps folded away.
  import InstallItForMe from './InstallItForMe.svelte'
  import ManualSteps from './ManualSteps.svelte'
  import StatusMark from './StatusMark.svelte'
  import type { CheckRow } from '../../lib/checkRows.ts'
  import type { ConnectForm, VerifyResult } from '../../lib/types.ts'

  let { row, form, fingerprint, onChecked }: { row: CheckRow; form: ConnectForm; fingerprint: string; onChecked: (result: VerifyResult) => void } = $props()
</script>

<li class="row" data-check={row.id} data-state={row.state}>
  <StatusMark kind={row.state} />
  <div class="body">
    <div class="lbl">{row.label}</div>
    {#if row.sentence}<div class="det">{row.sentence}</div>{/if}
    {#if row.manual}<ManualSteps steps={row.manual} />{/if}
  </div>
  {#if row.value}<span class="val">{row.value}</span>{/if}
  {#if row.install}<InstallItForMe offer={row.install} {form} {fingerprint} {onChecked} />{/if}
</li>

<style>
  .row { display: grid; grid-template-columns: 22px minmax(0, 1fr) auto; column-gap: 12px; align-items: start; padding: 8px 0; }
  .row > :global(.mark) { margin-top: 1px; }
  .body { min-width: 0; overflow-wrap: anywhere; }
  .lbl { font-weight: 600; }
  .det { color: var(--m70); font-size: 13px; }
  .val { color: var(--m70); font-size: 13px; text-align: right; overflow-wrap: anywhere; padding-top: 1px; }
  @media (max-width: 520px) { .val { max-width: 42vw; } }
</style>
