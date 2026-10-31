<script lang="ts">
  // The Security tab of a machine's page: who is knocking and what is blocked. Read only. The machine's own report comes with the machine
  // (Machine.security); a machine that sent none gets a plain "Not reporting yet" instead of zeros, because a machine that does not report is not being watched.
  import BaselineBlock from './BaselineBlock.svelte'
  import BlockedTable from './BlockedTable.svelte'
  import LoginsTable from './LoginsTable.svelte'
  import NamesBlock from './NamesBlock.svelte'
  import NotReporting from './NotReporting.svelte'
  import SummaryBlock from './SummaryBlock.svelte'
  import { securityOf } from '../../lib/security.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine, now }: { machine: Machine; now: number } = $props()
  const report = $derived(securityOf(machine))
</script>

<section class="security" aria-label="Security">
  {#if report === null}
    <NotReporting {machine} />
  {:else}
    <BaselineBlock {report} />
    <SummaryBlock {report} />
    <BlockedTable {report} {now} />
    <NamesBlock {report} />
    <LoginsTable {report} {now} />
  {/if}
</section>

<style>
  .security { display: grid; gap: 16px; max-width: 980px; min-width: 0; }
</style>
