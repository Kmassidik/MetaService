<script lang="ts">
  // A computer's screen in the panel. It opens as view only; mouse and keyboard need a separate confirmed step. The picture is drawn on a canvas, never as page content.
  import Dialog from './Dialog.svelte'
  import { ApiError, closeScreen, openScreen, screenPicture, sendScreenInput, takeScreenControl } from '../lib/api.ts'
  import { batch, buttonName, macKeyCode, pointerPosition, scrollSteps } from '../lib/screen.ts'
  import type { ScreenInput, ScreenSession } from '../lib/types.ts'

  interface Props {
    machine: string
    name: string
    open: boolean
    onClose: () => void
  }

  let { machine, name, open, onClose }: Props = $props()

  const FRAME_GAP_MS = 150
  const RETRY_MS = 1000
  const FLUSH_MS = 50
  const SESSION_GONE = [404, 410]

  let session = $state<ScreenSession | null>(null)
  let problem = $state('')
  let ended = $state('')
  let confirming = $state(false)
  let canvas: HTMLCanvasElement | undefined = $state()
  let queue: ScreenInput[] = []
  let active = false

  const controlling = $derived(session?.mode === 'control')

  const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms))

  async function start() {
    problem = ''
    ended = ''
    confirming = false
    try {
      session = await openScreen(machine)
    } catch (error) {
      problem = error instanceof ApiError ? error.message : 'Could not open the screen.'
      return
    }
    active = true
    void showPictures(session.ticket)
    void flushInput(session.ticket)
  }

  async function showPictures(ticket: string) {
    while (active) {
      try {
        const bitmap = await screenPicture(ticket)
        draw(bitmap)
        await sleep(FRAME_GAP_MS)
      } catch (error) {
        if (error instanceof ApiError && SESSION_GONE.includes(error.status)) return finish(error.message)
        await sleep(RETRY_MS)
      }
    }
  }

  function draw(bitmap: ImageBitmap) {
    const surface = canvas
    const context = surface?.getContext('2d')
    if (!surface || !context) return
    if (surface.width !== bitmap.width || surface.height !== bitmap.height) {
      surface.width = bitmap.width
      surface.height = bitmap.height
    }
    context.drawImage(bitmap, 0, 0)
    bitmap.close()
  }

  async function flushInput(ticket: string) {
    while (active) {
      await sleep(FLUSH_MS)
      if (queue.length === 0 || !controlling) continue
      const events = batch(queue)
      queue = []
      try {
        await sendScreenInput(ticket, events)
      } catch (error) {
        if (error instanceof ApiError && SESSION_GONE.includes(error.status)) return finish(error.message)
      }
    }
  }

  function finish(reason: string) {
    active = false
    ended = reason
  }

  async function takeControl() {
    if (!session) return
    try {
      session = await takeScreenControl(session.ticket)
      confirming = false
      canvas?.focus()
    } catch (error) {
      problem = error instanceof ApiError ? error.message : 'Could not switch control on.'
    }
  }

  async function end() {
    active = false
    const ticket = session?.ticket
    session = null
    if (ticket) await closeScreen(ticket).catch(() => null)
    onClose()
  }

  function push(event: ScreenInput) {
    if (controlling) queue.push(event)
  }

  function onMove(event: PointerEvent) {
    if (!canvas) return
    push({ type: 'move', ...pointerPosition(event.clientX, event.clientY, canvas.getBoundingClientRect()) })
  }

  function onButton(event: PointerEvent, down: boolean) {
    onMove(event)
    push({ type: 'button', button: buttonName(event.button), down })
  }

  function onWheel(event: WheelEvent) {
    if (!controlling) return
    event.preventDefault()
    push({ type: 'scroll', ...scrollSteps(event.deltaX, event.deltaY) })
  }

  function onKey(event: KeyboardEvent, down: boolean) {
    const code = macKeyCode(event.code)
    if (!controlling || code === null) return
    event.preventDefault()
    push({ type: 'key', code, down })
  }

  $effect(() => {
    if (open) void start()
    return () => {
      active = false
      const ticket = session?.ticket
      if (ticket) void closeScreen(ticket).catch(() => null)
      session = null
    }
  })
</script>

<Dialog {open} title="Screen of {name}" onClose={end} wide>
  {#if problem}
    <p class="problem" role="alert">{problem}</p>
  {:else if ended}
    <p class="problem" role="alert">{ended} Close this and open the screen again.</p>
  {/if}

  <div class="bar" class:live={controlling}>
    <span class="mode">{controlling ? `You are controlling ${name}` : 'View only'}</span>
    <span class="grow"></span>
    {#if session && !controlling && !confirming}<button class="btn line sm" type="button" onclick={() => (confirming = true)}>Take control</button>{/if}
    <button class="btn danger sm" type="button" onclick={end}>End</button>
  </div>

  {#if confirming}
    <div class="confirm" role="alert">
      <p>Use the mouse and keyboard of <b>{name}</b> from this page? Everything you type goes to that computer.</p>
      <button class="btn green sm" type="button" onclick={takeControl}>Yes, take control</button>
      <button class="btn line sm" type="button" onclick={() => (confirming = false)}>No, keep viewing</button>
    </div>
  {/if}

  <canvas
    bind:this={canvas}
    class="screen"
    class:live={controlling}
    tabindex="0"
    aria-label="Screen of {name}"
    onpointermove={onMove}
    onpointerdown={(event) => onButton(event, true)}
    onpointerup={(event) => onButton(event, false)}
    onwheel={onWheel}
    onkeydown={(event) => onKey(event, true)}
    onkeyup={(event) => onKey(event, false)}
    oncontextmenu={(event) => controlling && event.preventDefault()}
  ></canvas>
</Dialog>

<style>
  .bar { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1px solid var(--gray); font-family: var(--mono); font-size: 12px; }
  .bar.live { border-color: var(--green); background: var(--gray2); font-weight: 700; }
  .grow { flex: 1; }
  .confirm { border: 1px solid var(--black); padding: 12px; display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
  .confirm p { flex-basis: 100%; margin: 0; }
  .screen { display: block; width: 100%; height: auto; max-height: 70vh; object-fit: contain; background: var(--black); border: 1px solid var(--gray); touch-action: none; outline: none; }
  .screen.live { border-color: var(--green); cursor: crosshair; }
  .problem { margin: 0; padding: 10px 12px; border: 1px solid var(--black); font-family: var(--mono); font-size: 12px; }
</style>
