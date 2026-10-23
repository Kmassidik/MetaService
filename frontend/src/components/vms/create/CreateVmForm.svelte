<script lang="ts">
  // The inside of the Create VM window: the host, then server image, install on top, size, runtime and GPU, an optional name, and the footer. It is built fresh each time the window opens.
  import { onMount, tick } from 'svelte'
  import ActionButton from '../../ActionButton.svelte'
  import GpuChoice from '../../GpuChoice.svelte'
  import FieldBlock from './FieldBlock.svelte'
  import ImageSections from './ImageSections.svelte'
  import MachinePick from './MachinePick.svelte'
  import RuntimeSelect from './RuntimeSelect.svelte'
  import SizeSelect from './SizeSelect.svelte'
  import { ActionState } from '../../../lib/action.svelte.ts'
  import { ApiError, createWorkload, getMachineImages, refusalText } from '../../../lib/api.ts'
  import { blankForm, machineChoices, machineOptions, pickMachine, runtimeCards, startingMachine, type NewVmForm } from '../../../lib/createVm.ts'
  import { gpuMemoryProblem, gpuOffer, sharedPartition } from '../../../lib/gpuChoice.ts'
  import { nameProblem, workloadBody, workloadProblem } from '../../../lib/format.ts'
  import { imageAfterChange, imageOptions, STOCK_IMAGE, type MachineImages } from '../../../lib/images.ts'
  import { trackCreateAnswer } from '../../../lib/pendingStore.svelte.ts'
  import { FAILED_MESSAGE } from '../../../lib/timeouts.ts'
  import type { Machine } from '../../../lib/types.ts'
  import { EXAMPLE_GENERATED_NAME, nameToSend } from '../../../lib/vmName.ts'
  import { sizeCards } from '../../../lib/vmSize.ts'

  const MACHINE_ID = 'vm-create-machine'
  const NAME_ID = 'vm-create-name'
  const IMAGE_ID = 'vm-create-image'
  const FRAMEWORK_ID = 'vm-create-framework'
  const SIZE_ID = 'vm-create-size'
  const RUNTIME_ID = 'vm-create-runtime'
  const FIRST_CONTROL = 'select:not(:disabled), input:not(:disabled)'
  const NAME_EXAMPLE = 'e.g. build-box'
  const SPACE_SENTENCE = 'The host re-checks available memory and disk space before provisioning.'
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
  const gpuProblem = $derived(gpuMemoryProblem(form.gpuMode, form.gpuMemoryGb, sharedPartition(pickedMachine, gpuOffer(pickedMachine, form.kind))))
  const problem = $derived(workloadProblem({ ...form, name: form.name || EXAMPLE_GENERATED_NAME }) ?? sizeReason ?? gpuProblem)
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
  <div class="scroll">
  <fieldset disabled={action.busy}>
    <MachinePick id={MACHINE_ID} options={machineOptions(choices, only?.id ?? null)} value={form.machine} locked={only !== null} onpick={pickMachineById} />
    <ImageSections serverId={IMAGE_ID} frameworkId={FRAMEWORK_ID} options={images} bundle={form.bundle} unreadable={imagesUnreadable} onpick={(bundle) => (form.bundle = bundle)} />
    <SizeSelect id={SIZE_ID} cards={sizes} chosen={form.size} bind:form onpick={(key) => (form.size = key)} />
    <RuntimeSelect id={RUNTIME_ID} cards={runtimes} chosen={form.kind} os={pickedMachine?.os} onpick={(kind) => (form.kind = kind)} />
    <GpuChoice bind:form machine={pickedMachine} />
    <FieldBlock label="Instance name" note="(optional)" forId={NAME_ID}>
      <input id={NAME_ID} bind:value={form.name} autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="63" placeholder={NAME_EXAMPLE} aria-invalid={form.name !== '' && nameProblem(form.name) !== null ? 'true' : 'false'} />
    </FieldBlock>
  </fieldset>
  </div>
  <footer>
    <p class="hint" class:bad={problem !== null}>{problem ?? SPACE_SENTENCE}</p>
    <div class="buttons">
      <button class="btn line" type="button" onclick={onClose} disabled={action.busy}>Cancel</button>
      <ActionButton variant="green" label="Create VM" busyLabel="Creating…" doneLabel="Ordered" {action} disabled={!ready} onrun={order} />
    </div>
  </footer>
</form>

<style>
  /* The window's title bar and padding take this much of the screen; the form keeps the rest, scrolls its fields inside it, and leaves the footer in view. */
  form { --window-chrome: 130px; display: flex; flex-direction: column; gap: 14px; max-height: calc(100dvh - var(--window-chrome)); }
  .scroll { flex: 1 1 auto; min-height: 0; overflow-y: auto; margin: -4px; padding: 4px; }
  fieldset { display: grid; gap: 24px; border: 0; margin: 0; padding: 0; min-width: 0; }
  input { min-height: 44px; padding: 0 12px; border: 1px solid var(--reserve-line); border-radius: 0; background: var(--surface); color: var(--text); font: 400 14px var(--mono); min-width: 0; }
  input:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: 2px; border-color: var(--line-strong); }
  input[aria-invalid='true'] { border-color: var(--danger); }
  footer { display: flex; align-items: center; gap: 12px 16px; flex-wrap: wrap; flex: none; padding-top: 14px; border-top: 1px solid var(--line); }
  .hint { flex: 1 1 200px; margin: 0; font: 12px/1.5 var(--mono); color: var(--m50); }
  .hint.bad { color: var(--danger); }
  .buttons { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-left: auto; }
</style>
