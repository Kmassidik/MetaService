<script lang="ts">
  import Bar from './Bar.svelte'
  import { formatBytes, percentOf } from '../../lib/stats.ts'
  import type { StatsDisk } from '../../lib/types.ts'

  let { disks }: { disks: StatsDisk[] } = $props()
</script>

<section class="block" aria-label="Disks">
  <h3>Disk</h3>
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
</section>

<style>
  .block { display: grid; gap: 10px; align-content: start; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .vol { display: grid; gap: 4px; }
  .top { display: flex; justify-content: space-between; gap: 8px; font-family: var(--mono); font-size: 12px; }
  .mount { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
