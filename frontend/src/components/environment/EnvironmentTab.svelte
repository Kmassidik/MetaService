<script lang="ts">
  // The Environment tab: what the machine is, what is on it, Ruvio on or off, limits, what a new VM gets, and names. One Save; changes apply to new VMs only.
  import { untrack } from 'svelte'
  import MachineFacts from './MachineFacts.svelte'
  import SoftwareSection from './SoftwareSection.svelte'
  import RuvioSection from './RuvioSection.svelte'
  import LimitsSection from './LimitsSection.svelte'
  import VmDefaultsSection from './VmDefaultsSection.svelte'
  import NamesSection from './NamesSection.svelte'
  import { ApiError, machineExtras, updateHelper, updateMachineSettings } from '../../lib/api.ts'
  import { ruvioView, softwareRows } from '../../lib/environment.ts'
  import { formErrors, formFromMachine, patchFor, sameForm } from '../../lib/environmentForm.ts'
import { failureView, helperView, outcomeView, type OutcomeView } from '../../lib/helperUpdate.ts'
  import type { MachineExtras } from '../../lib/machineDetail.ts'
  import type { Machine, RemoteMachineInfo } from '../../lib/types.ts'

  const POLL_WHILE_GOING_MS = 2000
  const SAVED_TEXT = 'Saved. The changes apply to new VMs only.'

  interface Props {
    machine: Machine
    remote: RemoteMachineInfo | null
    now: number
    /** The highest helper version any machine reports, to mark an old one. */
    newestHelper: string | null
    /** How many chat versions the parent has built. */
    chatsBuilt: number
    /** Turns Ruvio on or off. Answers the parent's refusal text, or null when it went through. */
    onRuvio: (machine: Machine, on: boolean) => Promise<string | null>
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
  let saving = $state(false)
  let saveFailure = $state('')
  let saved = $state(false)
  let ruvioFailure = $state('')
  let updating = $state(false)
  let updateOutcome: OutcomeView | null = $state(null)
  let asked = 0

  const full = $derived<Machine>({ ...machine, ...(extras ?? {}) })
  const errors = $derived(formErrors(form))
  const dirty = $derived(!sameForm(form, loadedFrom))
  const canSave = $derived(dirty && Object.keys(errors).length === 0 && !saving)
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

  async function save() {
    if (!canSave) return
    saving = true
    saveFailure = ''
    saved = false
    try {
      await updateMachineSettings(machine.id, patchFor(form, machine))
      loadedFrom = { ...form }
      saved = true
      onChanged()
      await load()
    } catch (error) {
      saveFailure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      saving = false
    }
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

  async function switchRuvio(on: boolean) {
    ruvioFailure = (await onRuvio(machine, on)) ?? ''
    await load()
  }
</script>

<MachineFacts {machine} {now} />
{#if loadFailure}<p class="failure" role="alert">{loadFailure}</p>{/if}
{#if loaded}
  <SoftwareSection {rows} newest={newestHelper} {helper} {updating} outcome={updateOutcome} onUpdate={updateHelperNow} />
  <RuvioSection ruvio={full.ruvio} {view} failure={ruvioFailure} onSwitch={() => switchRuvio(!view.on)} onUpdate={() => switchRuvio(true)} onOpen={() => onOpenChat(machine, null)} />
{:else}
  <p class="loading" role="status">Loading…</p>
{/if}
<form onsubmit={(event) => { event.preventDefault(); save() }} novalidate>
  <LimitsSection bind:form {errors} />
  <VmDefaultsSection bind:form {errors} />
  <NamesSection bind:form {errors} />
  <div class="savebar">
    <button class="btn green" type="submit" disabled={!canSave}>{saving ? 'Saving…' : 'Save'}</button>
    <span class="apply">Changes apply to new VMs only.</span>
  </div>
  {#if saveFailure}<p class="failure" role="alert">{saveFailure}</p>{/if}
  {#if saved && !dirty}<p class="done" role="status">{SAVED_TEXT}</p>{/if}
</form>

<style>
  .savebar { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; max-width: 820px; padding-top: 16px; border-top: 1px solid var(--line); }
  .loading { margin: 0 0 24px; color: var(--m50); font: 12px var(--mono); }
  .apply { font-size: 12.5px; color: var(--m60); }
  .failure { max-width: 820px; margin: 12px 0; padding: 10px 12px; border: 1px solid var(--danger-note-line); border-left: 4px solid var(--danger-note-bar); background: var(--danger-note-bg); color: var(--danger-note-text); font-size: 13px; overflow-wrap: anywhere; }
  .done { max-width: 820px; margin: 12px 0 0; padding: 10px 12px; border: 1px solid var(--ok-note-line); border-left: 4px solid var(--ok); background: var(--ok-note-bg); color: var(--ok-note-text); font-size: 13px; }
</style>
