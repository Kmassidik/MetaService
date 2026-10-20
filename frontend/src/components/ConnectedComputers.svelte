<script lang="ts">
  // Connect a computer: the computers already connected over SSH, and the button that starts connecting another one.
  import StatePill from './StatePill.svelte'
  import { machineHref } from '../lib/routes.ts'
  import { connectionText, isolationText } from '../lib/remote.ts'
  import type { Machine, RemoteMachineInfo } from '../lib/types.ts'

  let { infos, machines, now, onConnect, onRemove }: { infos: RemoteMachineInfo[]; machines: Machine[]; now: number; onConnect: () => void; onRemove: (machine: Machine) => void } = $props()
  const machineOf = (info: RemoteMachineInfo) => machines.find((machine) => machine.id === info.machine)
</script>

<section class="connected">
  <div class="top">
    <div>
      <h2>Connect a computer</h2>
      <p class="muted">Computers MetaService reaches over SSH. Connecting another one only looks first and installs nothing until you say so.</p>
    </div>
    <button class="btn green" type="button" onclick={onConnect}>Connect a computer</button>
  </div>

  {#if infos.length === 0}
    <p class="muted">No computer is connected yet.</p>
  {:else}
    <div class="table" role="table" aria-label="Connected computers">
      <div class="head" role="row"><span>Computer</span><span>Address</span><span>Isolation</span><span>Connection</span><span></span></div>
      {#each infos as info (info.machine)}
        {@const machine = machineOf(info)}
        <div class="row" role="row">
          <span class="who" data-label="Computer"><a href={machineHref(info.machine)}>{info.machine}</a>{#if machine}<StatePill state={machine.state} />{/if}</span>
          <span class="mono address" data-label="Address">{info.ssh_user}@{info.host}:{info.ssh_port}</span>
          <span data-label="Isolation">{isolationText(info.level)}</span>
          <span class="muted" data-label="Connection">{connectionText(info, now)}</span>
          <span class="end">{#if machine}<button class="btn line sm" type="button" onclick={() => onRemove(machine)}>Remove</button>{/if}</span>
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .connected { display: grid; gap: 16px; }
  .top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; flex-wrap: wrap; }
  .top > div { flex: 1; min-width: 260px; }
  .who { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .address { overflow-wrap: anywhere; }
  h2 { font-size: 20px; }
  .table { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
  .head, .row { display: grid; grid-template-columns: minmax(150px, 1fr) minmax(200px, 1.4fr) minmax(110px, 0.8fr) minmax(180px, 1.4fr) 90px; gap: 12px; align-items: center; padding: 10px 16px; }
  .head { background: var(--surface-2); color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
  .row { border-top: 1px solid var(--line); }
  .end { display: flex; justify-content: flex-end; }
  @media (max-width: 900px) {
    .head { display: none; }
    .row { grid-template-columns: 1fr; padding: 14px; gap: 6px; }
    .row > span[data-label]::before { content: attr(data-label) ': '; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
  }
</style>
