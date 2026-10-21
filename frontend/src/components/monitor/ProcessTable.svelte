<script lang="ts">
  // Read only: program name and who started it, never a command line. Everything is text. The box narrows the list by name or account.
  import { formatBytes, formatProcessCpu } from '../../lib/stats.ts'
  import { filterProcesses } from '../../lib/processList.ts'
  import type { StatsProcess } from '../../lib/types.ts'

  const NOTE = 'The programs that use the most of this machine. "Run by" is the account that started the program.'

  /** `processes` null: the first answer with the list has not arrived yet. */
  let { processes, onClose }: { processes: StatsProcess[] | null; onClose: () => void } = $props()
  let filter = $state('')
  const rows = $derived(filterProcesses(processes ?? [], filter))
</script>

{#if processes === null}
  <p class="none" role="status">Reading the programs…</p>
{:else}
  {#if processes.length > 0}
    <input class="fld" type="search" placeholder="Filter by name or account" aria-label="Filter the processes by name or account" bind:value={filter} />
  {/if}
  <div class="wrap">
    <table class="procs" data-testid="process-table">
      <thead><tr><th>Name</th><th>Run by</th><th class="r">CPU</th><th class="r">Memory</th></tr></thead>
      <tbody>
        {#each rows as process (process.pid)}
          <tr><td class="name">{process.name}</td><td class="user">{process.user}</td><td class="r nums">{formatProcessCpu(process.cpu_percent)}</td><td class="r nums">{formatBytes(process.memory_bytes)}</td></tr>
        {:else}
          <tr><td colspan="4" class="none">{filter.trim() === '' ? 'Nothing to list yet.' : 'No program matches that.'}</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}
<p class="note">{NOTE}</p>
<div class="actions"><button class="btn line" type="button" onclick={onClose}>Close</button></div>

<style>
  .note { margin: 0; font-size: 12px; color: var(--m50); }
  .actions { display: flex; justify-content: flex-end; }
  .wrap { overflow-x: auto; }
  .procs { width: 100%; border-collapse: collapse; font-family: var(--mono); font-size: 12px; }
  th { text-align: left; font-size: 10px; font-weight: 400; text-transform: uppercase; letter-spacing: 0.08em; color: var(--m40); padding: 0 8px 6px; border-bottom: 1px solid var(--line); }
  td { padding: 5px 8px; border-bottom: 1px solid var(--surface-2); }
  .r { text-align: right; }
  .name { max-width: 380px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 700; }
  .user { color: var(--m60); max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  @media (max-width: 520px) { .procs th:nth-child(2), .procs td.user { display: none; } }
  .none { margin: 0; color: var(--m50); }
</style>
