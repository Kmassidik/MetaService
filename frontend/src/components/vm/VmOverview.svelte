<script lang="ts">
  // The Overview tab of a VM: the same rows as the MAAS detail page, then the chat buttons.
  import WhyStopped from './WhyStopped.svelte'
  import { isPlainMode, PLAIN_MODE_TEXT, type StopNote } from '../../lib/stoppedReason.ts'
  import { vmFacts } from '../../lib/vm.ts'
  import type { BuildingServer } from '../../lib/building.ts'
  import type { Machine, Workload } from '../../lib/types.ts'

  interface Props {
    machine: Machine
    workload: Workload
    server: BuildingServer
    pinned: string | null | undefined
    /** Why a stopped VM stopped; null when it is not stopped. */
    note: StopNote | null
    onInstall: () => void
  }

  let { machine, workload, server, pinned, note, onInstall }: Props = $props()
  const facts = $derived(vmFacts(machine, workload, pinned))
</script>

<dl class="kv">
  {#each facts as fact (fact.label)}
    <div><dt>{fact.label}</dt><dd>{#if fact.value === null}<span class="tag {server.cls}">{server.status}</span>{:else}<span class="mono">{fact.value}</span>{/if}</dd></div>
  {/each}
</dl>
{#if note}<div class="extra"><WhyStopped {note} /></div>{/if}
{#if isPlainMode(workload)}<p class="extra plain">{PLAIN_MODE_TEXT}</p>{/if}
{#if workload.state === 'running'}
  <div class="chatbar"><button class="btn line sm" type="button" onclick={onInstall}>{workload.bundle_version ? 'Reinstall chat' : 'Install chat'}</button></div>
{/if}

<style>
  .kv { display: grid; gap: 14px; margin: 0; }
  .kv > div { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 16px; border-bottom: 1px solid var(--surface-2); padding-bottom: 12px; }
  .kv dt { font-family: var(--mono); font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--m50); }
  .kv dd { margin: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; overflow-wrap: anywhere; }
  .chatbar { display: flex; gap: 8px; margin-top: 20px; }
  .extra { margin-top: 20px; }
  .plain { margin-bottom: 0; font-size: 13px; color: var(--m70); }
  @media (max-width: 820px) { .kv > div { grid-template-columns: 1fr; gap: 4px; } }
</style>
