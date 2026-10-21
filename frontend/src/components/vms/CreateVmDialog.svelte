<script lang="ts">
  // The one Create VM window: step 1 picks one of the machines already on the list, step 2 (only once one is picked) is the VM's name, kind and sizes.
  // On a machine's own page it opens with that machine chosen and locked (`only`); everywhere else the person picks.
  import { tick, untrack } from 'svelte'
  import Dialog from '../Dialog.svelte'
  import VmFields from './VmFields.svelte'
  import { ApiError, createWorkload, getMachineImages, refusalText } from '../../lib/api.ts'
  import { blankForm, kindAfterPick, kindChoices, machineChoices, machineDefaults, machineOptions, startingMachine, unavailableNotes, type NewVmForm } from '../../lib/createVm.ts'
  import { imageAfterChange, imageNotes, imageOptions, STOCK_IMAGE, type MachineImages } from '../../lib/images.ts'
  import { workloadBody, workloadProblem } from '../../lib/format.ts'
  import { trackCreateAnswer } from '../../lib/pendingStore.svelte.ts'
  import type { Machine } from '../../lib/types.ts'

  const MACHINE_ID = 'vm-create-machine'
  const NAME_ID = 'vm-create-name'
  const IMAGE_ID = 'vm-create-image'
  const IMAGES_UNREADABLE = 'The list of images could not be read, so only Blank is offered.'
  const UNREADABLE_ANSWER = 'The parent answered in a way this page cannot read. Look in All VMs to see whether the VM was made.'

  interface Props {
    open: boolean
    machines: Machine[]
    /** The address the window was opened from (for the machine it names), without the #. */
    route: string
    /** Set when opened from one machine's own page: the VM goes there and nowhere else. */
    only?: Machine | null
    onClose: () => void
    /** The VM was ordered: read the lists again so the "Creating…" card shows. */
    onCreated: () => void
  }

  let { open, machines, route, only = null, onClose, onCreated }: Props = $props()
  let form: NewVmForm = $state(blankForm(undefined))
  let busy = $state(false)
  let failure = $state('')
  let imageAnswer: MachineImages | null = $state(null)
  let imagesUnreadable = $state(false)
  let latestImageAsk = 0
  const choices = $derived(machineChoices(machines))
  const options = $derived(machineOptions(choices, only?.id ?? null))
  const notes = $derived(unavailableNotes(options))
  const picked = $derived(choices.find((choice) => choice.id === form.machine))
  const pickedMachine = $derived(machines.find((machine) => machine.id === form.machine))
  const kinds = $derived(kindChoices(picked))
  const images = $derived(imageOptions(imageAnswer))
  const imageLines = $derived([...imageNotes(images), ...(imagesUnreadable ? [IMAGES_UNREADABLE] : [])])
  const problem = $derived(form.name ? workloadProblem(form) : null)
  const ready = $derived(picked !== undefined && !picked.disabled && form.name !== '' && workloadProblem(form) === null)

  $effect(() => {
    // Opening the window, or following another address while it is open, starts it afresh; the lists refreshing every few seconds must not undo what is typed.
    void route
    if (!open) return
    untrack(() => {
      form = blankForm(machines.find((machine) => machine.id === startingMachine(route, only?.id ?? null, choices)))
      failure = ''
      busy = false
      void focusFirstField()
    })
  })

  // Another machine has other images ready: ask which, and keep to an image it can give.
  $effect(() => {
    const machine = form.machine
    untrack(() => void loadImages(machine))
  })

  $effect(() => {
    form.bundle = imageAfterChange(images, form.bundle ?? STOCK_IMAGE)
  })

  async function loadImages(machine: string) {
    const ask = ++latestImageAsk
    imageAnswer = null
    imagesUnreadable = false
    if (machine === '') return
    try {
      const answer = await getMachineImages(machine)
      if (ask === latestImageAsk) imageAnswer = answer
    } catch {
      if (ask === latestImageAsk) imagesUnreadable = true
    }
  }

  /** The first field is the machine, or the name when the machine is already chosen. */
  async function focusFirstField() {
    await tick()
    document.getElementById(form.machine ? NAME_ID : MACHINE_ID)?.focus()
  }

  /** Picking a machine fills in what a new VM gets on it, and keeps to a kind it can run. */
  function pick() {
    Object.assign(form, machineDefaults(pickedMachine))
    form.kind = kindAfterPick(picked, form.kind)
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    if (!ready || busy) return
    busy = true
    failure = ''
    try {
      const understood = trackCreateAnswer(await createWorkload(workloadBody(form)))
      onCreated()
      if (understood) onClose()
      else failure = UNREADABLE_ANSWER
    } catch (error) {
      failure = error instanceof ApiError ? refusalText(error) : 'Something went wrong.'
    } finally {
      busy = false
    }
  }
</script>

<Dialog {open} title="Create VM" {onClose} closeButton>
  {#if choices.length === 0}
    <div class="empty" role="status">No machines yet. Add one first, then make a VM on it.<a class="btn green sm" href="#/machines/find">Find machines</a></div>
  {:else}
    <form onsubmit={submit} novalidate>
      <section class="step" aria-labelledby="step-machine">
        <h2 id="step-machine">1 · Machine</h2>
        <label>Machine
          <select id={MACHINE_ID} bind:value={form.machine} onchange={pick} disabled={busy || only !== null}>
            {#if only === null}<option value="">Choose a machine</option>{/if}
            {#each options as choice (choice.id)}<option value={choice.id} disabled={choice.disabled}>{choice.label}</option>{/each}
          </select>
        </label>
        {#each notes as note (note)}<p class="muted note">{note}</p>{/each}
      </section>
      {#if picked}
        <section class="step" aria-labelledby="step-sizes">
          <h2 id="step-sizes">2 · The VM</h2>
          <fieldset disabled={busy}>
            <VmFields bind:form nameId={NAME_ID} imageId={IMAGE_ID} {kinds} {images} imageNotes={imageLines} nameProblem={problem} machine={pickedMachine} />
          </fieldset>
          <p class="hint {problem ? 'bad' : 'muted'}">{problem ?? 'The machine checks its own space again before it makes the VM.'}</p>
        </section>
      {/if}
      {#if failure}<p class="bad" role="alert">{failure}</p>{/if}
      <div class="row">
        <button class="btn line" type="button" onclick={onClose}>Cancel</button>
        <button class="btn green" type="submit" disabled={busy || !ready}>{busy ? 'Working…' : 'Create'}</button>
      </div>
    </form>
  {/if}
</Dialog>

<style>
  form { display: grid; gap: 14px; }
  .step { display: grid; gap: 10px; }
  fieldset { display: grid; gap: 10px; border: 0; margin: 0; padding: 0; min-width: 0; }
  label { display: grid; gap: 4px; font-weight: 600; font-size: 14px; }
  select { min-height: 40px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); font-weight: 400; max-width: 100%; }
  .note, .hint { font-size: 13px; margin: 0; }
  .bad { color: var(--danger); margin: 0; }
  .row { display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
</style>
