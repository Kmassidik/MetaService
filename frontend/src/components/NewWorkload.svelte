<script>
  import { untrack } from 'svelte'
  import Dialog from './Dialog.svelte'
  import { ApiError, createWorkload, refusalText } from '../lib/api.js'
  import { workloadBody, workloadProblem } from '../lib/format.js'

  /** `only` is set when the dialog was opened from one machine's own page: the VM goes there and nowhere else. */
  let { open, machines, only = null, onClose, onCreated } = $props()
  let form = $state({ name: '', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '' })
  let busy = $state(false)
  let failure = $state('')
  const problem = $derived(form.name ? workloadProblem(form) : null)
  const ready = $derived(form.name !== '' && workloadProblem(form) === null)

  $effect(() => {
    if (!open) return
    // Only opening the dialog resets it: what is typed afterwards must not make this run again.
    untrack(() => {
      form = { name: '', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: only?.id ?? '' }
      if (only) useMachineDefaults()
      failure = ''
      busy = false
    })
  })

  /** Picking a machine fills in what a new VM gets on it, if that machine was set up with such sizes. */
  function useMachineDefaults() {
    const settings = machines.find((machine) => machine.id === form.machine)?.settings
    if (!settings) return
    if (settings.vm_cpu) form.cpu = settings.vm_cpu
    if (settings.vm_ram_mb) form.ramGb = settings.vm_ram_mb / 1024
    if (settings.vm_disk_gb) form.diskGb = settings.vm_disk_gb
  }

  async function submit(event) {
    event.preventDefault()
    if (!ready) return
    busy = true
    failure = ''
    try {
      await createWorkload(workloadBody(form))
      onCreated()
      onClose()
    } catch (error) {
      failure = error instanceof ApiError ? refusalText(error) : 'Something went wrong.'
    } finally {
      busy = false
    }
  }
</script>

<Dialog {open} title="Create a VM" {onClose}>
  <form onsubmit={submit} novalidate>
    <label for="wl-name">Name</label>
    <input id="wl-name" bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder="build-box" aria-invalid={problem ? 'true' : 'false'} />
    <div class="grid">
      <label>Kind
        <select bind:value={form.kind}><option value="vm">VM</option><option value="container">Container</option></select>
      </label>
      <label>CPU <input type="number" min="1" max="64" step="1" bind:value={form.cpu} /></label>
      <label>RAM (GB) <input type="number" min="0.5" max="1024" step="0.5" bind:value={form.ramGb} /></label>
      <label>Disk (GB) <input type="number" min="1" max="100000" step="1" bind:value={form.diskGb} /></label>
    </div>
    <label>Machine
      <select bind:value={form.machine} onchange={useMachineDefaults}>
        {#if !only}<option value="">Any machine with room</option>{/if}
        {#each (only ? [only] : machines) as machine (machine.id)}<option value={machine.id}>{machine.name}{machine.state === 'offline' ? ' (offline)' : ''}</option>{/each}
      </select>
    </label>
    <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'The machine with the most room left is picked, and it checks its own space again.'}</p>
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <button class="btn line" type="button" onclick={onClose}>Cancel</button>
      <button class="btn green" type="submit" disabled={busy || !ready}>{busy ? 'Asking…' : 'Create'}</button>
    </div>
  </form>
</Dialog>

<style>
  form { display: grid; gap: 10px; }
  label { display: grid; gap: 4px; font-weight: 600; font-size: 14px; }
  input, select { min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); font-weight: 400; }
  input[aria-invalid='true'] { border-color: var(--danger); }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 10px; }
  .hint { font-size: 13px; }
  .bad { color: var(--danger); }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
</style>
