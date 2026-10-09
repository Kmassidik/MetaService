<script>
  import Dialog from './Dialog.svelte'
  import { ApiError, createWorkload, refusalText } from '../lib/api.js'
  import { workloadBody, workloadProblem } from '../lib/format.js'

  let { open, machines, onClose, onCreated } = $props()
  let form = $state({ name: '', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '' })
  let busy = $state(false)
  let failure = $state('')
  const problem = $derived(form.name ? workloadProblem(form) : null)
  const ready = $derived(form.name !== '' && workloadProblem(form) === null)

  $effect(() => {
    if (open) {
      form = { name: '', kind: 'vm', cpu: 2, ramGb: 2, diskGb: 20, machine: '' }
      failure = ''
      busy = false
    }
  })

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

<Dialog {open} title="New workload" {onClose}>
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
      <select bind:value={form.machine}>
        <option value="">Any machine with room</option>
        {#each machines as machine (machine.id)}<option value={machine.id}>{machine.name}{machine.state === 'offline' ? ' (offline)' : ''}</option>{/each}
      </select>
    </label>
    <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'The Root picks the machine with the most room left, and the machine checks its own space again.'}</p>
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
