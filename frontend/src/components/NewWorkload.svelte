<script lang="ts">
  import { untrack } from 'svelte'
  import Dialog from './Dialog.svelte'
  import VmFields from './vms/VmFields.svelte'
  import { ApiError, createWorkload, refusalText } from '../lib/api.ts'
  import { blankForm, kindAfterPick, kindChoices, machineChoice, machineDefaults, type NewVmForm } from '../lib/createVm.ts'
  import { workloadBody, workloadProblem } from '../lib/format.ts'
  import { trackCreateAnswer } from '../lib/pendingStore.svelte.ts'
  import type { Machine } from '../lib/types.ts'

  /** `only` is set when the dialog was opened from one machine's own page: the VM goes there and nowhere else. */
  let { open, machines, only = null, onClose, onCreated }: { open: boolean; machines: Machine[]; only?: Machine | null; onClose: () => void; onCreated: () => void } = $props()
  let form: NewVmForm = $state(blankForm(undefined))
  let busy = $state(false)
  let failure = $state('')
  const problem = $derived(form.name ? workloadProblem(form) : null)
  const ready = $derived(form.name !== '' && workloadProblem(form) === null)
  const picked = $derived(machines.find((machine: Machine) => machine.id === form.machine))
  const kinds = $derived(kindChoices(picked ? machineChoice(picked) : undefined))

  $effect(() => {
    if (!open) return
    // Only opening the dialog resets it: what is typed afterwards must not make this run again.
    untrack(() => {
      form = blankForm(only ?? undefined)
      failure = ''
      busy = false
    })
  })

  /** Picking a machine fills in what a new VM gets on it, if that machine was set up with such sizes, and keeps to a kind it can run. */
  function useMachineDefaults() {
    Object.assign(form, machineDefaults(picked))
    form.kind = kindAfterPick(picked ? machineChoice(picked) : undefined, form.kind)
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    if (!ready) return
    busy = true
    failure = ''
    try {
      trackCreateAnswer(await createWorkload(workloadBody(form)))
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
    <VmFields bind:form nameId="wl-name" {kinds} nameProblem={problem} machine={picked} />
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
  select { min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); font-weight: 400; }
  .hint { font-size: 13px; }
  .bad { color: var(--danger); }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; }
</style>
