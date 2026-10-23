<script lang="ts">
  // The CPU, memory and disk rows of the Create VM window, laid out like Proxmox's Processors window: Sockets over Cores on the left, Type over Total cores on the right, then Memory and Disk.
  // A container shares the machine's CPU, so it has no sockets or CPU type: it gets Cores and a CPU limit. What the machine cannot set is off, with one plain line saying why.
  // Typing numbers moves the size select to the preset they match, or to Custom.
  import { coresPerSocket, cpuNote, HOST_MODEL, MAX_SOCKETS, MIN_LIMIT_CORES, ONE_SOCKET_TEXT, OLD_HELPER_LIMIT_NOTE, totalFromCores, totalFromSockets, type CpuOffer } from '../../../lib/cpuOptions.ts'
  import type { NewVmForm } from '../../../lib/createVm.ts'
  import type { Machine } from '../../../lib/types.ts'
  import { matchingSize } from '../../../lib/vmSize.ts'
  import CpuTypeCombo from './CpuTypeCombo.svelte'
  import FieldBlock from './FieldBlock.svelte'
  import SpinField from './SpinField.svelte'

  const MAX_CPU = 64
  const HOST_ONLY_REASON = "This machine gives a VM its own CPU only."
  const UNLIMITED = 'unlimited'

  let { form = $bindable(), offer, machine }: { form: NewVmForm; offer: CpuOffer; machine: Machine | undefined } = $props()
  const note = $derived(cpuNote(machine, form.kind, offer))

  /** The size line follows the numbers: a preset when they match one, else Custom. */
  const followSize = () => (form.size = matchingSize(form.cpu, form.ramGb, form.diskGb))

  function setCores(cores: string) {
    form.cpu = totalFromCores(cores, form)
    followSize()
  }

  function setSockets(sockets: string) {
    form.cpu = totalFromSockets(sockets, form)
    form.cpuSockets = sockets
    followSize()
  }

  function setMemory(gb: string) {
    form.ramGb = gb
    followSize()
  }

  function setDisk(gb: string) {
    form.diskGb = gb
    followSize()
  }
</script>

{#if form.kind === 'vm'}
  <SpinField id="vm-create-sockets" label="Sockets" value={form.cpuSockets ?? 1} min={1} max={MAX_SOCKETS} disabled={!offer.sockets} reason={offer.sockets ? null : ONE_SOCKET_TEXT} oninput={setSockets} />
  <CpuTypeCombo id="vm-create-cpu-type" models={offer.models} chosen={form.cpuType ?? HOST_MODEL} reason={offer.models.length > 1 ? null : HOST_ONLY_REASON} onpick={(model) => (form.cpuType = model === HOST_MODEL ? undefined : model)} />
  <SpinField id="vm-create-cores" label="Cores" value={coresPerSocket(form)} min={1} max={MAX_CPU} oninput={setCores} />
  <FieldBlock label="Total cores"><output class="total" for="vm-create-sockets vm-create-cores" data-total-cores>{form.cpu}</output></FieldBlock>
{:else}
  <SpinField id="vm-create-cores" label="Cores" value={form.cpu} min={1} max={MAX_CPU} oninput={setCores} />
  <SpinField id="vm-create-cpu-limit" label="CPU limit" value={form.cpuLimit} min={MIN_LIMIT_CORES} max={Math.max(MIN_LIMIT_CORES, Number(form.cpu) || 1)} step={0.1} placeholder={UNLIMITED} disabled={!offer.limit} reason={offer.limit ? null : OLD_HELPER_LIMIT_NOTE} oninput={(cores) => (form.cpuLimit = cores)} />
{/if}
<SpinField id="vm-create-memory" label="Memory (GB)" value={form.ramGb} min={0.5} max={1024} step={0.5} oninput={setMemory} />
<SpinField id="vm-create-disk" label="Disk (GB)" value={form.diskGb} min={1} max={100000} oninput={setDisk} />
{#if note}<p class="note" data-cpu-note>{note}</p>{/if}

<style>
  .total { display: block; padding-top: 6px; font: 600 13px/1.4 var(--sans); color: var(--text); }
  .note { grid-column: 1 / -1; margin: 0; padding: 7px 10px; border-left: 3px solid var(--reserve-line); background: var(--surface); font-size: 12px; line-height: 1.5; color: var(--m60); }
</style>
