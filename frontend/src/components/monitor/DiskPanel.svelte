<script lang="ts">
  import Bar from './Bar.svelte'
  import MetricCard from './MetricCard.svelte'
  import { formatBytes, percentOf } from '../../lib/stats.ts'
  import type { StatsDisk } from '../../lib/types.ts'

  let { disks }: { disks: StatsDisk[] } = $props()
</script>

<MetricCard label="Disk">
  <div class="vols">
    {#each disks as disk (disk.mount)}
      {@const used = percentOf(disk.used_bytes, disk.total_bytes)}
      <div class="vol">
        <div class="top"><span class="mount" title={disk.name}>{disk.mount}</span><span class="nums">{formatBytes(disk.used_bytes)} of {formatBytes(disk.total_bytes)}</span></div>
        <Bar percent={used} label="Disk {disk.mount} in use" />
        <div class="sub nums">{formatBytes(disk.free_bytes)} free · {disk.fs}</div>
      </div>
    {:else}
      <p class="sub">No disks reported.</p>
    {/each}
  </div>
</MetricCard>

<style>
  .vols { display: grid; gap: 12px; max-height: 220px; overflow-y: auto; }
  .vol { display: grid; gap: 4px; }
  .top { display: flex; justify-content: space-between; gap: 8px; font-family: var(--mono); font-size: 12px; }
  .mount { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
