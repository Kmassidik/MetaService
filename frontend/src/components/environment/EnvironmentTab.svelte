<script lang="ts">
  // The Environment tab: what the machine is, what is on it, Ruvio on or off, limits, what a new VM gets, and names. One Save; changes apply to new VMs only.
  import { untrack } from 'svelte'
  import CollapsibleSection from './CollapsibleSection.svelte'
  import MachineFacts from './MachineFacts.svelte'
  import SoftwareSection from './SoftwareSection.svelte'
  import RuvioSection from './RuvioSection.svelte'
  import LimitsSection from './LimitsSection.svelte'
  import VmDefaultsSection from './VmDefaultsSection.svelte'
  import NamesSection from './NamesSection.svelte'
  import SaveBar from './SaveBar.svelte'
  import { ActionState } from '../../lib/action.svelte.ts'
  import { ApiError, machineExtras, updateMachineSettings } from '../../lib/api.ts'
  import { ruvioView, softwareRows } from '../../lib/environment.ts'
  import { dirtySections, errorSections, undoneForm, type EditableSection } from '../../lib/environmentDirty.ts'
  import { formErrors, formFromMachine, patchFor, sameForm } from '../../lib/environmentForm.ts'
  import { limitsSummary, machineSummary, namesSummary, ruvioSummary, softwareSummary, vmDefaultsSummary } from '../../lib/environmentSummary.ts'
  import { helperView } from '../../lib/helperUpdate.ts'
  import { HelperUpdater } from '../../lib/helperUpdater.svelte.ts'
  import type { MachineExtras } from '../../lib/machineDetail.ts'
  import type { Machine, RemoteMachineInfo } from '../../lib/types.ts'

  const POLL_WHILE_GOING_MS = 2000
  const LOADING_SUMMARY = 'loading…'
  const ROW_IDS = ['machine', 'software', 'ruvio', 'limits', 'vmDefaults', 'names'] as const
  type RowId = (typeof ROW_IDS)[number]

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
  const updater = new HelperUpdater()
  let asked = 0
  /** Every row starts closed. Several may be open; a row with an error is held open by the row itself. */
  let opened: Record<RowId, boolean> = $state({ machine: false, software: false, ruvio: false, limits: false, vmDefaults: false, names: false })

  const full = $derived<Machine>({ ...machine, ...(extras ?? {}) })
  const errors = $derived(formErrors(form))
  const changedSections = $derived(dirtySections(form, loadedFrom))
  const errorRows = $derived(errorSections(errors))
  const dirty = $derived(changedSections.length > 0)
  const canSave = $derived(dirty && Object.keys(errors).length === 0 && !saveAction.busy)
  /** Unsaved changes, or the answer to the last Save for its moment on screen. */
  const showBar = $derived(dirty || saveAction.status !== 'idle')
  const view = $derived(ruvioView(full.ruvio, chatsBuilt, machine.state !== 'offline'))
  const rows = $derived(softwareRows(full, remote, newestHelper, now))
  const helper = $derived(helperView(full))
  const changed = (section: EditableSection): boolean => changedSections.includes(section)
  const failing = (section: EditableSection): boolean => errorRows.includes(section)
  const allOpen = $derived(ROW_IDS.every((id) => opened[id]))

  /** Opens every row, or closes every row that is not held open by an error. */
  function toggleAll() {
    const open = !allOpen
    for (const id of ROW_IDS) opened[id] = open || errorRows.some((section) => section === id)
  }

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
    await updater.run(machine.id)
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
  <div class="tools"><button class="expand" type="button" onclick={toggleAll}>{allOpen ? 'Collapse all' : 'Expand all'}</button></div>
  <div class="rows">
    <CollapsibleSection id="machine" title="This machine" summary={machineSummary(full)} bind:open={opened.machine}>
      <MachineFacts {machine} {now} />
    </CollapsibleSection>
    <CollapsibleSection id="software" title="Software" summary={loaded ? softwareSummary(helper.status) : LOADING_SUMMARY} bind:open={opened.software}>
      {#if loaded}
        <SoftwareSection {rows} newest={newestHelper} {helper} updating={updater.updating} outcome={updater.outcome} onUpdate={updateHelperNow} />
      {:else}
        <p class="loading" role="status">Loading…</p>
      {/if}
    </CollapsibleSection>
    <CollapsibleSection id="ruvio" title="Ruvio" intro="Ruvio is the chat. It is off until you turn it on." summary={loaded ? ruvioSummary(view.on, full.ruvio?.installed) : LOADING_SUMMARY} bind:open={opened.ruvio}>
      {#if loaded}
        <RuvioSection ruvio={full.ruvio} {view} onSwitch={() => switchRuvio(!view.on)} onUpdate={() => switchRuvio(true)} onOpen={() => onOpenChat(machine, null)} />
      {/if}
    </CollapsibleSection>
    <form aria-label="Settings" onsubmit={submit} novalidate>
      <CollapsibleSection id="limits" title="Limits" intro="Keep some of the machine free for itself, and cap what VMs may take." summary={limitsSummary(form)} changed={changed('limits')} error={failing('limits')} bind:open={opened.limits}>
        <LimitsSection bind:form {errors} />
      </CollapsibleSection>
      <CollapsibleSection id="vmDefaults" title="A new VM gets" intro="Create a VM here starts with these sizes." summary={vmDefaultsSummary(form)} changed={changed('vmDefaults')} error={failing('vmDefaults')} bind:open={opened.vmDefaults}>
        <VmDefaultsSection bind:form {errors} />
      </CollapsibleSection>
      <CollapsibleSection id="names" title="Names" summary={namesSummary(form)} changed={changed('names')} error={failing('names')} bind:open={opened.names}>
        <NamesSection bind:form {errors} />
      </CollapsibleSection>
      <!-- Lets Enter in a field save, as the visible Save button is in the bar below. -->
      <button class="sr-only" type="submit" tabindex="-1" aria-hidden="true"></button>
    </form>
  </div>
  {#if showBar}<SaveBar action={saveAction} {canSave} sections={changedSections.length} onSave={save} onUndo={undo} />{/if}
</div>

<style>
  .env { max-width: 820px; }
  .tools { display: flex; justify-content: flex-end; margin-bottom: 6px; }
  .expand { padding: 4px 0; border: 0; background: none; color: var(--m60); font: 12px var(--mono); text-decoration: underline; cursor: pointer; }
  .expand:hover { color: var(--text); }
  .expand:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; }
  .rows { border-top: 1px solid var(--line); margin-bottom: 16px; }
  .loading { margin: 0; color: var(--m50); font: 12px var(--mono); }
  .failure { max-width: 820px; margin: 0 0 12px; padding: 10px 12px; border: 1px solid var(--danger-note-line); border-left: 4px solid var(--danger-note-bar); background: var(--danger-note-bg); color: var(--danger-note-text); font-size: 13px; overflow-wrap: anywhere; }
</style>
