<script lang="ts">
  // Read only: program name and who started it, never a command line. Everything is text. Shows the top few; "Show all" lists every one, and the box narrows the list by name or account.
  import { formatBytes, formatProcessCpu } from '../../lib/stats.ts'
  import { visibleProcesses } from '../../lib/processList.ts'
  import type { StatsProcess } from '../../lib/types.ts'

  const NOTE = 'The programs that use the most of this machine. "Run by" is the account that started the program.'

  let { processes }: { processes: StatsProcess[] } = $props()
  let filter = $state('')
  let showAll = $state(false)
  const view = $derived(visibleProcesses(processes, filter, showAll))
</script>

<section class="block" aria-label="Processes">
  <div class="head">
    <h3>Top processes</h3>
    {#if processes.length > 0}
      <input class="fld" type="search" placeholder="Filter by name or account" aria-label="Filter the processes by name or account" bind:value={filter} />
    {/if}
  </div>
  <div class="wrap">
    <table class="procs">
      <thead><tr><th>Name</th><th>Run by</th><th class="r">CPU</th><th class="r">Memory</th></tr></thead>
      <tbody>
        {#each view.rows as process (process.pid)}
          <tr><td class="name">{process.name}</td><td class="user">{process.user}</td><td class="r nums">{formatProcessCpu(process.cpu_percent)}</td><td class="r nums">{formatBytes(process.memory_bytes)}</td></tr>
        {:else}
          <tr><td colspan="4" class="none">{filter.trim() === '' ? 'Nothing to list yet.' : 'No program matches that.'}</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if view.canExpand}
    <button class="btn line sm more" type="button" aria-expanded={showAll} onclick={() => (showAll = !showAll)}>{showAll ? 'Show fewer' : `Show all ${view.total}`}</button>
  {/if}
  <p class="note">{NOTE}</p>
</section>

<style>
  .block { display: grid; gap: 8px; min-width: 0; }
  .head { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .head .fld { width: auto; min-width: 200px; max-width: 100%; }
  .more { justify-self: start; }
  .note { margin: 0; font-size: 12px; color: var(--m50); }
  .wrap { overflow-x: auto; }
  .procs { width: 100%; border-collapse: collapse; font-family: var(--mono); font-size: 12px; }
  th { text-align: left; font-size: 10px; font-weight: 400; text-transform: uppercase; letter-spacing: 0.08em; color: var(--m40); padding: 0 8px 6px; border-bottom: 1px solid var(--gray); }
  td { padding: 5px 8px; border-bottom: 1px solid var(--gray2); }
  .r { text-align: right; }
  .name { max-width: 280px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 700; }
  .user { color: var(--m60); max-width: 140px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  @media (max-width: 520px) { .procs th:nth-child(2), .procs td.user { display: none; } }
  .none { color: var(--m50); }
</style>
