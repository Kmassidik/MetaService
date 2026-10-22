<script lang="ts">
  // The Environment tab: what the machine is, what is on it, Ruvio on or off, limits, what a new VM gets, and names. One Save; changes apply to new VMs only.
  import { untrack } from 'svelte'
  import MachineFacts from './MachineFacts.svelte'
  import SoftwareSection from './SoftwareSection.svelte'
  import RuvioSection from './RuvioSection.svelte'
  import LimitsSection from './LimitsSection.svelte'
  import VmDefaultsSection from './VmDefaultsSection.svelte'
  import NamesSection from './NamesSection.svelte'
  import SaveBar from './SaveBar.svelte'
  import { ActionState } from '../../lib/action.svelte.ts'
  import { ApiError, machineExtras, updateHelper, updateMachineSettings } from '../../lib/api.ts'
  import { ruvioView, softwareRows } from '../../lib/environment.ts'
  import { isDirty, undoneForm } from '../../lib/environmentDirty.ts'
  import { formErrors, formFromMachine, patchFor, sameForm } from '../../lib/environmentForm.ts'
  import { failureView, helperView, outcomeView, type OutcomeView } from '../../lib/helperUpdate.ts'
  import type { MachineExtras } from '../../lib/machineDetail.ts'
  import type { Machine, RemoteMachineInfo } from '../../lib/types.ts'

  const POLL_WHILE_GOING_MS = 2000

  interface Props {
    machine: Machine
    remote: RemoteMachineInfo | null
    now: number
    /** The highest helper version any machine reports, to mark an old one. */
    newestHelper: string | null
    /** How many chat versions the parent has built. */
    chatsBuilt: number
    /** Turns Ruvio on or off. Throws the parent's refusal. */
    onRuvio: (machine: Machine, on: boolean) => Promise<unknown>
    onOpenChat: (machine: Machine, workload: null) => void
    /** Something changed on the parent: read the machines again. */
    onChanged: () => void
  }

  let { machine, remote, now, newestHelper, chatsBuilt, onRuvio, onOpenChat, onChanged }: Props = $props()

  let extras: MachineExtras | null = $state(null)
  /** False until the machine's own page has been read once, so a value is never shown as "not reported" only because it is still on its way. */
  let loaded = $state(false)
  let loadFailure = $state('')
  let form = $state(untrack(() => formFromMachine(machine)))
  let loadedFrom = $state(untrack(() => formFromMachine(machine)))
  const saveAction = new ActionState()
  let updating = $state(false)
  let updateOutcome: OutcomeView | null = $state(null)
  let asked = 0

  const full = $derived<Machine>({ ...machine, ...(extras ?? {}) })
  const errors = $derived(formErrors(form))
  const dirty = $derived(isDirty(form, loadedFrom))
  const canSave = $derived(dirty && Object.keys(errors).length === 0 && !saveAction.busy)
  /** Unsaved changes, or the answer to the last Save for its moment on screen. */
  const showBar = $derived(dirty || saveAction.status !== 'idle')
  const view = $derived(ruvioView(full.ruvio, chatsBuilt, machine.state !== 'offline'))
  const rows = $derived(softwareRows(full, remote, newestHelper, now))
  const helper = $derived(helperView(full))

  /** Reads the parts of the machine that only its own page carries. Only the newest answer counts. */
  async function load() {
    const turn = ++asked
    try {
      const answer = await machineExtras(machine.id)
      if (turn === asked) extras = answer
      loadFailure = ''
    } catch (error) {
      loadFailure = error instanceof Error ? error.message : 'Something went wrong.'
    } finally {
      loaded = true
    }
  }

  // The machine is read again every time the list is, and the form follows the machine unless the person has started editing.
  $effect(() => {
    const fresh = formFromMachine(machine)
    untrack(() => {
      if (sameForm(form, loadedFrom)) form = fresh
      loadedFrom = fresh
      load()
    })
  })

  // While a command is going, look again soon so the switch moves by itself.
  $effect(() => {
    const going = extras?.ruvio?.state === 'installing' || extras?.ruvio?.state === 'removing'
    if (!going) return
    const timer = setTimeout(() => { load(); onChanged() }, POLL_WHILE_GOING_MS)
    return () => clearTimeout(timer)
  })

  /** Sends the changed fields. Throws the parent's refusal, which the Save button shows beside itself. */
  async function save() {
    try {
      await updateMachineSettings(machine.id, patchFor(form, machine))
    } catch (error) {
      throw error instanceof ApiError ? error : new Error('Something went wrong.')
    }
    loadedFrom = { ...form }
    onChanged()
    await load()
  }

  const undo = () => { form = undoneForm(loadedFrom) }

  const saveIfAllowed = () => { if (canSave) void saveAction.run(save) }

  function submit(event: SubmitEvent) {
    event.preventDefault()
    saveIfAllowed()
  }

  /** Replaces the helper program with the newest one. The answer is told in words; the machine is read again, and its next report carries the new build. */
  async function updateHelperNow() {
    if (updating) return
    updating = true
    updateOutcome = null
    try {
      updateOutcome = outcomeView(await updateHelper(machine.id))
    } catch (error) {
      updateOutcome = error instanceof ApiError ? failureView(error.code, error.message) : failureView('error', 'Something went wrong.')
    } finally {
      updating = false
    }
    onChanged()
    await load()
  }

  /** The machine is read again either way, so the switch shows what is true; a refusal is thrown to the control that asked. */
  async function switchRuvio(on: boolean) {
    try {
      await onRuvio(machine, on)
    } finally {
      await load()
    }
  }
</script>

{#if loadFailure}<p class="failure" role="alert">{loadFailure}</p>{/if}
<div class="env">
  <div class="col">
    <MachineFacts {machine} {now} />
    {#if loaded}
      <SoftwareSection {rows} newest={newestHelper} {helper} {updating} outcome={updateOutcome} onUpdate={updateHelperNow} />
    {:else}
      <p class="loading" role="status">Loading…</p>
    {/if}
  </div>
  <div class="col">
    {#if loaded}
      <RuvioSection ruvio={full.ruvio} {view} onSwitch={() => switchRuvio(!view.on)} onUpdate={() => switchRuvio(true)} onOpen={() => onOpenChat(machine, null)} />
    {/if}
    <form aria-label="Settings" onsubmit={submit} novalidate>
      <LimitsSection bind:form {errors} />
      <VmDefaultsSection bind:form {errors} />
      <NamesSection bind:form {errors} />
      <!-- Lets Enter in a field save, as the visible Save button is in the bar below. -->
      <button class="sr-only" type="submit" tabindex="-1" aria-hidden="true"></button>
    </form>
  </div>
  {#if showBar}<SaveBar action={saveAction} {canSave} onSave={save} onUndo={undo} />{/if}
</div>

<style>
  .env { display: grid; grid-template-columns: minmax(0, 1fr); max-width: 820px; }
  .col { min-width: 0; }
  .loading { margin: 0 0 24px; color: var(--m50); font: 12px var(--mono); }
  .failure { max-width: 820px; margin: 0 0 12px; padding: 10px 12px; border: 1px solid var(--danger-note-line); border-left: 4px solid var(--danger-note-bar); background: var(--danger-note-bg); color: var(--danger-note-text); font-size: 13px; overflow-wrap: anywhere; }
  /* Wide screen: what the machine is on the left, what you can change on the right, both starting at the same top edge. */
  @media (min-width: 1100px) {
    .env { grid-template-columns: minmax(0, 5fr) minmax(0, 6fr); column-gap: 32px; align-items: start; max-width: none; }
  }
</style>
