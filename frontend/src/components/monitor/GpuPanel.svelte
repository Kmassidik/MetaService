<script lang="ts">
  // The details of every GPU the machine reported: maker, name, use, memory, and what could be read (temperature, power, fan, clock).
  // Only what was readable is drawn; the history is in the charts above. NVIDIA also lists the programs that hold GPU memory.
  import Bar from './Bar.svelte'
  import MetricCard from './MetricCard.svelte'
  import { bookingPercent, bookingText, type GpuBooking } from '../../lib/gpuBooking.ts'
  import { gpuFacts, MAC_NOTE, memoryText, NO_PROGRAMS_TEXT, showsMacNote, vendorLabel } from '../../lib/gpuView.ts'
  import { formatBytes, formatPercent, percentOf } from '../../lib/stats.ts'
  import type { StatsGpu } from '../../lib/types.ts'

  let { gpus, booking = null }: { gpus: StatsGpu[]; booking?: GpuBooking | null } = $props()
  const memoryPercent = (gpu: StatsGpu) => (gpu.memory_used_bytes !== null && gpu.memory_total_bytes ? percentOf(gpu.memory_used_bytes, gpu.memory_total_bytes) : null)
</script>

<MetricCard label="GPU">
  {#each gpus as gpu, index (index)}
    {@const memory = memoryText(gpu)}
    <div class="gpu" data-testid="gpu-{index}">
      <div class="top"><span class="chip" data-testid="gpu-vendor">{vendorLabel(gpu)}</span><span class="name">{gpu.name}</span></div>
      {#if gpu.utilization_percent !== null}
        <div class="line"><span>Use</span><span class="nums">{formatPercent(gpu.utilization_percent)}</span></div>
        <Bar percent={gpu.utilization_percent} label="GPU in use" />
      {/if}
      {#if memory !== null}
        <div class="line"><span>Memory</span><span class="nums">{memory}</span></div>
        {#if memoryPercent(gpu) !== null}<Bar percent={memoryPercent(gpu)} label="GPU memory in use" />{/if}
      {/if}
      {#each gpuFacts(gpu) as fact (fact.key)}
        <div class="line"><span>{fact.label}</span><span class="nums" data-testid="gpu-{fact.key}">{fact.value}</span></div>
      {/each}
      {#if gpu.processes !== undefined}
        <div class="programs" data-testid="gpu-programs">
          <h4>Programs using the GPU</h4>
          {#if gpu.processes.length === 0}
            <p class="none">{NO_PROGRAMS_TEXT}</p>
          {:else}
            <ul>{#each gpu.processes as program, at (at)}<li><span class="pname">{program.name}</span><span class="nums">{formatBytes(program.memory_bytes)}</span></li>{/each}</ul>
          {/if}
        </div>
      {/if}
    </div>
  {/each}
  {#if booking !== null}
    <div class="booking" data-testid="gpu-booking">
      <div class="line"><span>{bookingText(booking)}</span></div>
      <Bar percent={bookingPercent(booking)} label="GPU memory booked for VMs" />
    </div>
  {/if}
  {#if showsMacNote(gpus)}<p class="note" data-testid="gpu-mac-note">{MAC_NOTE}</p>{/if}
</MetricCard>

<style>
  .gpu { display: grid; gap: 4px; }
  .gpu + .gpu { border-top: 1px solid var(--line); padding-top: 10px; }
  .top, .line, li { display: flex; justify-content: space-between; gap: 8px; font-family: var(--mono); font-size: 12px; }
  .top { justify-content: flex-start; align-items: center; }
  .chip { flex: none; padding: 1px 6px; border: 1px solid var(--line); background: var(--surface-2); font-size: 10px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--m60); }
  .name, .pname { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  .line { font-size: 11px; color: var(--m60); }
  .booking { display: grid; gap: 4px; border-top: 1px solid var(--line); padding-top: 10px; }
  .programs { display: grid; gap: 3px; margin-top: 4px; }
  h4 { margin: 0; font-family: var(--mono); font-size: 10px; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; color: var(--m50); }
  ul { margin: 0; padding: 0; list-style: none; display: grid; gap: 2px; }
  li { font-size: 11px; }
  li .pname { font-weight: 400; }
  .none, .note { margin: 0; font-size: 12px; color: var(--m60); }
  .note { margin-top: 4px; }
</style>
