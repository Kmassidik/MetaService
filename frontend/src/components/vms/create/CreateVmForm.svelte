<script lang="ts">
  // The inside of the Create VM window: machine, then IMAGE, SIZE and RUNTIME cards, an optional name, and the footer. It is built fresh each time the window opens.
  import { onMount, tick } from 'svelte'
  import ActionButton from '../../ActionButton.svelte'
  import GpuChoice from '../../GpuChoice.svelte'
  import ImageCards from './ImageCards.svelte'
  import MachinePick from './MachinePick.svelte'
  import RuntimeCards from './RuntimeCards.svelte'
  import SizeCards from './SizeCards.svelte'
  import { ActionState } from '../../../lib/action.svelte.ts'
  import { ApiError, createWorkload, getMachineImages, refusalText } from '../../../lib/api.ts'
  import { blankForm, machineChoices, machineOptions, pickMachine, runtimeCards, startingMachine, type NewVmForm } from '../../../lib/createVm.ts'
  import { nameProblem, workloadBody, workloadProblem } from '../../../lib/format.ts'
  import { imageAfterChange, imageCards, imageOptions, STOCK_IMAGE, type MachineImages } from '../../../lib/images.ts'
  import { trackCreateAnswer } from '../../../lib/pendingStore.svelte.ts'
  import { FAILED_MESSAGE } from '../../../lib/timeouts.ts'
  import type { Machine } from '../../../lib/types.ts'
  import { EXAMPLE_GENERATED_NAME, nameToSend } from '../../../lib/vmName.ts'
  import { sizeCards } from '../../../lib/vmSize.ts'

  const MACHINE_ID = 'vm-create-machine'
  const NAME_ID = 'vm-create-name'
  const IMAGE_GROUP = 'vm-create-image'
  const SIZE_GROUP = 'vm-create-size'
  const RUNTIME_GROUP = 'vm-create-runtime'
  const FIRST_CONTROL = 'select:not(:disabled), input:not(:disabled)'
  const NAME_EXAMPLE = 'e.g. build-box'
  const SPACE_SENTENCE = 'The machine checks its own space again before it makes the VM.'
  const UNREADABLE_ANSWER = 'The parent answered in a way this page cannot read. Look in All VMs to see whether the VM was made.'

  interface Props {
    machines: Machine[]
    /** The address the window was opened from (for the machine it names), without the #. */
    route: string
    /** Set when opened from one machine's own page: the VM goes there and nowhere else. */
    only: Machine | null
    /** True while the order is on its way: the window must stay open. */
    busy: boolean
    onClose: () => void
    /** The VM was ordered: read the lists again so the "Creating…" card shows. */
    onCreated: () => void
  }

  let { machines, route, only, busy = $bindable(), onClose, onCreated }: Props = $props()
  const choices = $derived(machineChoices(machines))
  const startingForm = (): NewVmForm => blankForm(machines.find((machine) => machine.id === startingMachine(route, only?.id ?? null, choices)))
  let form: NewVmForm = $state(startingForm())
  let imageAnswer: MachineImages | null = $state(null)
  let imagesUnreadable = $state(false)
  let latestImageAsk = 0
  let formElement: HTMLFormElement | undefined
  const action = new ActionState()
  const picked = $derived(choices.find((choice) => choice.id === form.machine))
  const pickedMachine = $derived(machines.find((machine) => machine.id === form.machine))
  const images = $derived(imageOptions(imageAnswer))
  const sizes = $derived(sizeCards(pickedMachine))
  const runtimes = $derived(runtimeCards(picked))
  const sizeReason = $derived(sizes.find((card) => card.key === form.size)?.reason ?? null)
  const problem = $derived(workloadProblem({ ...form, name: form.name || EXAMPLE_GENERATED_NAME }) ?? sizeReason)
  const ready = $derived(picked !== undefined && !picked.disabled && problem === null)

  $effect(() => {
    busy = action.busy
    return () => (busy = false)
  })

  onMount(() => {
    void focusFirstControl()
  })

  // Another machine has other images ready: ask which, and keep to an image it can give.
  $effect(() => {
    const machine = form.machine
    void loadImages(machine)
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

  /** The machine select, or the first card when the machine is already fixed. */
  async function focusFirstControl() {
    await tick()
    formElement?.querySelector<HTMLElement>(FIRST_CONTROL)?.focus()
  }

  const pickMachineById = (id: string) => (form = pickMachine(form, machines.find((machine) => machine.id === id)))

  /** The order, as the busy-guarded button runs it: it throws the plain failure so the button shows it, and closes the window when the parent understood. */
  async function order() {
    const taken = new Set(pickedMachine?.workloads.map((workload) => workload.name))
    const body = workloadBody({ ...form, name: nameToSend(form.name, Math.random, taken) })
    const understood = trackCreateAnswer(await createWorkload(body).catch(failure))
    onCreated()
    if (!understood) throw new Error(UNREADABLE_ANSWER)
    onClose()
  }

  function failure(error: unknown): never {
    throw new Error(error instanceof ApiError ? refusalText(error) : FAILED_MESSAGE)
  }

  function submit(event: SubmitEvent) {
    event.preventDefault()
    if (ready) void action.run(order)
  }
</script>

<form bind:this={formElement} onsubmit={submit} novalidate aria-label="Create VM">
  <fieldset disabled={action.busy}>
    <MachinePick id={MACHINE_ID} options={machineOptions(choices, only?.id ?? null)} value={form.machine} locked={only !== null} onpick={pickMachineById} />
    <ImageCards group={IMAGE_GROUP} cards={imageCards(images)} chosen={form.bundle ?? STOCK_IMAGE} unreadable={imagesUnreadable} onpick={(id) => (form.bundle = id)} />
    <SizeCards group={SIZE_GROUP} cards={sizes} chosen={form.size} bind:form onpick={(key) => (form.size = key)} />
    <RuntimeCards group={RUNTIME_GROUP} cards={runtimes} chosen={form.kind} onpick={(kind) => (form.kind = kind)} />
    <GpuChoice bind:form machine={pickedMachine} />
    <div class="name">
      <label for={NAME_ID}>Name <span class="optional">optional</span></label>
      <input id={NAME_ID} bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder={NAME_EXAMPLE} aria-invalid={form.name !== '' && nameProblem(form.name) !== null ? 'true' : 'false'} />
    </div>
  </fieldset>
  <footer>
    <p class="hint" class:bad={problem !== null}>{problem ?? SPACE_SENTENCE}</p>
    <div class="buttons">
      <button class="btn line" type="button" onclick={onClose} disabled={action.busy}>Cancel</button>
      <ActionButton variant="green" label="Create VM" busyLabel="Creating…" doneLabel="Ordered" {action} disabled={!ready} onrun={order} />
    </div>
  </footer>
</form>

<style>
  form { display: grid; gap: 14px; }
  fieldset { display: grid; gap: 16px; border: 0; margin: 0; padding: 0; min-width: 0; }
  .name { display: grid; gap: 8px; }
  .name label { font: 700 10px var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--m50); }
  .optional { font-weight: 400; letter-spacing: 0; text-transform: none; color: var(--m40); }
  .name input { min-height: 40px; padding: 0 10px; border: 1px solid var(--line); background: var(--surface); color: var(--text); font: 400 14px var(--mono); min-width: 0; }
  .name input[aria-invalid='true'] { border-color: var(--danger); }
  footer { position: sticky; bottom: 0; display: flex; align-items: center; gap: 12px 16px; flex-wrap: wrap; margin: 0 -22px -20px; padding: 14px 22px; border-top: 1px solid var(--line); background: var(--surface); }
  .hint { flex: 1 1 200px; margin: 0; font: 10px/1.5 var(--mono); color: var(--m40); }
  .hint.bad { color: var(--danger); }
  .buttons { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-left: auto; }
</style>
