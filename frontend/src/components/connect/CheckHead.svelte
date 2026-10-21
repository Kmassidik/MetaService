<script lang="ts">
  // The top of the Check step: the ring, the machine in one line, the short host key with Copy, and what is left to do.
  import CopyButton from './CopyButton.svelte'
  import ProgressRing from './ProgressRing.svelte'
  import { hostKeyShort, machineLine, readyCount, verdict } from '../../lib/checkRows.ts'
  import type { CheckRow } from '../../lib/checkRows.ts'
  import type { VerifyResult } from '../../lib/types.ts'

  let { result, rows }: { result: VerifyResult; rows: CheckRow[] } = $props()
  const counts = $derived(readyCount(rows))
  const line = $derived(verdict(rows))
</script>

<div class="head">
  <ProgressRing done={counts.ready} total={counts.total} alt="{counts.ready} of {counts.total} checks ready" tone={line.tone} />
  <div class="who">
    <p class="sys">{result.system || result.host}</p>
    <p class="meta">{machineLine(result.facts)}</p>
    <p class="hostkey">Host key <code title={result.fingerprint}>{hostKeyShort(result.fingerprint)}</code><CopyButton text={result.fingerprint} describe="the host key" /></p>
    <p class="verdict {line.tone}" role="status">{line.text}</p>
  </div>
</div>

<style>
  .head { display: flex; gap: 16px; align-items: center; }
  .who { min-width: 0; }
  p { margin: 0; overflow-wrap: anywhere; }
  .sys { font-weight: 700; font-size: 16px; }
  .meta { font-size: 13px; color: var(--m70); }
  .hostkey { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 4px; font-size: 12px; color: var(--m70); }
  code { font-family: var(--mono); }
  .verdict { margin-top: 6px; font-size: 13px; font-weight: 600; }
  @media (max-width: 520px) { .head { flex-direction: column; align-items: flex-start; } }
</style>
