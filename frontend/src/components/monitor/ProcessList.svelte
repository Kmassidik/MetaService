<script lang="ts">
  // Read only: program name and user, never a command line. Everything is text.
  import { formatBytes, formatProcessCpu } from '../../lib/stats.ts'
  import type { StatsProcess } from '../../lib/types.ts'

  let { processes }: { processes: StatsProcess[] } = $props()
</script>

<section class="block" aria-label="Processes">
  <h3>Top processes</h3>
  <div class="wrap">
    <table class="procs">
      <thead><tr><th>Name</th><th>User</th><th class="r">CPU</th><th class="r">Memory</th></tr></thead>
      <tbody>
        {#each processes as process (process.pid)}
          <tr><td class="name">{process.name}</td><td class="user">{process.user}</td><td class="r nums">{formatProcessCpu(process.cpu_percent)}</td><td class="r nums">{formatBytes(process.memory_bytes)}</td></tr>
        {:else}
          <tr><td colspan="4" class="none">Nothing to list yet.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
</section>

<style>
  .block { display: grid; gap: 8px; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
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
