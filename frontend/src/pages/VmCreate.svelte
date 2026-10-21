<script lang="ts">
  // Create VM: step 1 picks one of the machines already on the list, step 2 is the same form the machine page has. The VM is made on that machine, and its page opens.
  import { onDestroy, untrack } from 'svelte'
  import VmFields from '../components/vms/VmFields.svelte'
  import { ApiError, createWorkload, newVmDeps, refusalText } from '../lib/api.ts'
  import { blankForm, kindAfterPick, kindChoices, machineChoices, machineDefaults, preselectedMachine, unavailableNotes, type NewVmForm } from '../lib/createVm.ts'
  import { workloadBody, workloadProblem } from '../lib/format.ts'
  import { awaitNewVm, parseCreated } from '../lib/newVm.ts'
  import { vmHref, vmsHref } from '../lib/routes.ts'
  import type { Machine } from '../lib/types.ts'

  const UNREADABLE_ANSWER = 'The parent answered in a way this page cannot read. Look in All VMs to see whether the VM was made.'
  const STILL_MAKING = 'The machine is still making it.'

  let { machines, route, banner, onCreated }: { machines: Machine[]; route: string; banner: string; onCreated: () => void } = $props()
  const choices = $derived(machineChoices(machines))
  const notes = $derived(unavailableNotes(choices))
  // Only opening the page picks a machine from the address: the list refreshes every few seconds and must not undo what is typed.
  let form: NewVmForm = $state(untrack(() => blankForm(machines.find((machine) => machine.id === preselectedMachine(route, choices)))))
  let busy = $state(false)
  let making = $state('')
  let failure = $state('')
  let slow = $state(false)
  let left = false
  const picked = $derived(choices.find((choice) => choice.id === form.machine))
  const kinds = $derived(kindChoices(picked))
  const problem = $derived(form.name ? workloadProblem(form) : null)
  const ready = $derived(picked !== undefined && !picked.disabled && form.name !== '' && workloadProblem(form) === null)

  onDestroy(() => (left = true))

  /** Picking a machine fills in what a new VM gets on it, and keeps to a kind it can run. */
  function pick() {
    Object.assign(form, machineDefaults(machines.find((machine) => machine.id === form.machine)))
    form.kind = kindAfterPick(picked, form.kind)
  }

  async function follow(answer: unknown) {
    const created = parseCreated(answer)
    if (!created) {
      failure = UNREADABLE_ANSWER
      return
    }
    making = `Making ${form.name} on ${picked?.name ?? created.machine}…`
    const outcome = await awaitNewVm(created, form.name, newVmDeps(() => left))
    if (left) return
    if (outcome.kind === 'ready') location.hash = vmHref(outcome.machine, outcome.workload)
    if (outcome.kind === 'failed') failure = outcome.message
    slow = outcome.kind === 'slow'
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    if (!ready || busy) return
    busy = true
    failure = ''
    slow = false
    try {
      const answer = await createWorkload(workloadBody(form))
      onCreated()
      await follow(answer)
    } catch (error) {
      failure = error instanceof ApiError ? refusalText(error) : 'Something went wrong.'
    } finally {
      busy = false
      making = ''
    }
  }
</script>

<div class="phead">
  <h1>Create VM</h1><span class="crumb">Infrastructure › on one of your machines</span>
</div>
{#if banner}<p class="banner" role="status">{banner}</p>{/if}
{#if choices.length === 0}
  <div class="empty" role="status">No machines yet. Add one first, then make a VM on it.<a class="btn green sm" href="#/machines/find">Find machines</a></div>
{:else}
  <form class="body" onsubmit={submit} novalidate>
    <section class="step" aria-labelledby="step-machine">
      <h2 id="step-machine">1 · Machine</h2>
      <label>Machine
        <select id="vm-create-machine" bind:value={form.machine} onchange={pick} disabled={busy}>
          <option value="">Choose a machine</option>
          {#each choices as choice (choice.id)}<option value={choice.id} disabled={choice.disabled}>{choice.label}</option>{/each}
        </select>
      </label>
      {#each notes as note (note)}<p class="muted note">{note}</p>{/each}
    </section>
    {#if picked}
      <section class="step" aria-labelledby="step-sizes">
        <h2 id="step-sizes">2 · The VM</h2>
        <fieldset disabled={busy}>
          <VmFields bind:form nameId="vm-create-name" {kinds} nameProblem={problem} />
        </fieldset>
        <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'The machine checks its own space again before it makes the VM.'}</p>
      </section>
    {/if}
    {#if making}<p class="muted" role="status">{making}</p>{/if}
    {#if slow}<p class="muted" role="status">{STILL_MAKING} It will show in <a href={vmsHref(form.machine)}>All VMs</a> when it is done.</p>{/if}
    {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
    <div class="row">
      <a class="btn line" href={vmsHref(null)}>Cancel</a>
      <button class="btn green" type="submit" disabled={busy || !ready}>{busy ? 'Working…' : 'Create'}</button>
    </div>
  </form>
{/if}

<style>
  form { max-width: 640px; }
  .step { display: grid; gap: 10px; }
  fieldset { display: grid; gap: 10px; border: 0; margin: 0; padding: 0; min-width: 0; }
  label { display: grid; gap: 4px; font-weight: 600; font-size: 14px; }
  select { min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); font-weight: 400; max-width: 100%; }
  .note, .hint { font-size: 13px; margin: 0; }
  .bad { color: var(--danger); margin: 0; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
</style>
