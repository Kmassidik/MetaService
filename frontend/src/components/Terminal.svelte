<script lang="ts">
  // The web terminal of one running VM: a modal with xterm, joined to the VM's shell through the Root. Same look and behaviour as the MAAS Terminal.
  // Every connection (the first and each Reconnect) asks the Root for a new one-use ticket.
  import { onMount } from 'svelte'
  import { Terminal } from '@xterm/xterm'
  import { FitAddon } from '@xterm/addon-fit'
  import '@xterm/xterm/css/xterm.css'
  import WhyStopped from './vm/WhyStopped.svelte'
  import { ApiError, openTerminal } from '../lib/api.ts'
  import { isDead, isLive, nextState, resizeMessage, roundBox, shouldRefit, SOCKET_OPEN, statusText, statusTone, terminalSocketUrl } from '../lib/terminal.ts'
  import type { Box, TerminalEvent, TerminalState } from '../lib/terminal.ts'
  import { NOTICE_STATUS, START_GIVE_UP_MS, START_POLL_MS, terminalNotice, type Ending } from '../lib/terminalNotice.ts'
  import type { StopNote } from '../lib/stoppedReason.ts'
  import type { Workload } from '../lib/types.ts'

  interface Props {
    machine: string
    workload: string
    /** The VM's name in the title. */
    name: string
    onclose: () => void
    /** The VM as the machine list shows it now, or null when it is not in the list. */
    vm: Workload | null
    /** Why the VM stopped, when it is stopped. */
    note: StopNote | null
    /** Starts the VM (the same order as the Start button of its page). */
    onstart: () => void
    /** Asks the panel to read the machines again, so the state and the reason are fresh. */
    onchanged: () => void
  }

  const FIRST_FIT_DELAY_MS = 50
  const TERMINAL_OPTIONS = {
    cursorBlink: true,
    fontFamily: "'Space Mono',ui-monospace,monospace",
    fontSize: 13,
    scrollback: 5000,
    theme: { background: '#111111', foreground: '#e8e8e8', cursor: '#00f56d', selectionBackground: '#00f56d', selectionForeground: '#111111' },
  }

  let { machine, workload, name, onclose, vm, note, onstart, onchanged }: Props = $props()
  let host: HTMLDivElement | undefined
  let phase: TerminalState = $state('connecting')
  let reason = $state('')
  /** How the terminal ended, for the message in the window; null while it works. */
  let ending: Ending | null = $state(null)
  let openedAt = 0
  let starting = $state(false)
  const term = new Terminal(TERMINAL_OPTIONS)
  const fit = new FitAddon()
  let socket: WebSocket | undefined
  let asking = false
  let disposed = false

  const notice = $derived(terminalNotice(ending, vm ? vm.state : null))
  const text = $derived(notice ? NOTICE_STATUS : statusText(phase, reason))
  const tone = $derived(notice ? '' : statusTone(phase))
  const dead = $derived(isDead(phase))
  const canReconnect = $derived(dead && !notice?.canStart)

  /** After Start, ask for the VM's state until it runs, then open the terminal again by itself. */
  $effect(() => {
    if (!starting) return
    const poll = setInterval(onchanged, START_POLL_MS)
    const giveUp = setTimeout(() => (starting = false), START_GIVE_UP_MS)
    return () => {
      clearInterval(poll)
      clearTimeout(giveUp)
    }
  })

  $effect(() => {
    if (!starting || vm?.state !== 'running') return
    starting = false
    void connect()
  })

  function start() {
    starting = true
    onstart()
  }

  function happened(event: TerminalEvent) {
    phase = nextState(phase, event)
  }

  function sendResize() {
    if (socket?.readyState === SOCKET_OPEN) socket.send(resizeMessage(term.cols, term.rows))
  }

  function refit() {
    try {
      fit.fit()
    } catch {
      // The box has no size yet (still opening); the observer fits again when it gets one.
    }
  }

  function onOpen() {
    openedAt = Date.now()
    happened('open')
    setTimeout(() => {
      if (disposed) return
      refit()
      sendResize()
      term.focus()
    }, FIRST_FIT_DELAY_MS)
  }

  function onMessage(event: MessageEvent<unknown>) {
    const data = event.data
    if (typeof data === 'string') term.write(data)
    if (data instanceof ArrayBuffer) term.write(new Uint8Array(data))
  }

  function attach(ws: WebSocket) {
    ws.binaryType = 'arraybuffer'
    ws.onopen = onOpen
    ws.onmessage = onMessage
    ws.onerror = () => happened('error')
    ws.onclose = (event) => {
      if (disposed) return
      reason = event.reason
      ending = { kind: 'closed', reason: event.reason, openMs: openedAt === 0 ? 0 : Date.now() - openedAt }
      openedAt = 0
      happened('close')
      onchanged()
    }
    socket = ws
  }

  function failed(error: unknown) {
    reason = error instanceof ApiError ? error.message : 'Cannot reach the Root.'
    ending = error instanceof ApiError ? { kind: 'refused', code: error.code } : null
    happened('error')
    onchanged()
  }

  /** A new ticket, then a new socket. Does nothing while one is already being asked for, opening or open. */
  async function connect() {
    if (asking || (socket && isLive(socket.readyState))) return
    asking = true
    reason = ''
    ending = null
    happened('connect')
    let ticket: string
    try {
      ticket = await openTerminal(machine, workload)
    } catch (error) {
      failed(error)
      return
    } finally {
      asking = false
    }
    if (!disposed) attach(new WebSocket(terminalSocketUrl(location, ticket)))
  }

  /** Fits when the box really changed, at most once per animation frame: fit() nudges the layout, which fires the observer again. */
  function watchSize(element: HTMLElement): ResizeObserver {
    let last: Box = { width: 0, height: 0 }
    let framePending = false
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0]
      const next = entry ? roundBox(entry.contentRect) : last
      if (entry && !shouldRefit(last, next)) return
      last = next
      if (framePending) return
      framePending = true
      requestAnimationFrame(() => {
        framePending = false
        refit()
      })
    })
    observer.observe(element)
    return observer
  }

  onMount(() => {
    if (!host) return
    term.loadAddon(fit)
    term.open(host)
    term.onResize(sendResize)
    const encoder = new TextEncoder()
    // Registered once, so a Reconnect never sends a keystroke twice.
    term.onData((typed) => {
      if (socket?.readyState === SOCKET_OPEN) socket.send(encoder.encode(typed))
    })
    const observer = watchSize(host)
    requestAnimationFrame(refit)
    void connect()
    return () => {
      // Closing the window ends the socket (and with it the shell on the VM) and frees xterm.
      disposed = true
      observer.disconnect()
      socket?.close()
      term.dispose()
    }
  })
</script>

<div class="modal" role="presentation" tabindex="-1" onclick={(event) => event.target === event.currentTarget && onclose()} onkeydown={(event) => event.key === 'Escape' && onclose()}>
  <div class="modal-box term-box">
    <div class="thead">
      <span class="ttitle">Terminal · {name}</span>
      <span class="tstatus {tone}">● {text}</span>
      <span class="tspace"></span>
      {#if canReconnect}<button class="tbtn" type="button" onclick={() => void connect()}>Reconnect</button>{/if}
      <button class="tbtn" type="button" onclick={onclose} aria-label="Close terminal">✕ Close</button>
    </div>
    <div class="term" class:away={notice !== null} bind:this={host}></div>
    {#if notice}
      <div class="notice" role="status">
        <p class="ntext">{notice.text}</p>
        {#if notice.why && note}<WhyStopped {note} />{/if}
        <div class="nact">
          {#if notice.canStart}<button class="btn green sm" type="button" disabled={starting} onclick={start}>{starting ? 'Starting…' : 'Start the VM'}</button>{/if}
          <button class="btn line sm" type="button" onclick={onclose}>Close</button>
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  /* fills most of the viewport; the terminal itself flexes to fill all space below the header */
  .term-box { width: min(1000px, 96vw); height: 82vh; display: flex; flex-direction: column; background: var(--black); border-color: #000; }
  .thead { flex-shrink: 0; display: flex; align-items: center; gap: 12px; padding: 9px 14px; background: #1a1a1a; border-bottom: 1px solid #000; }
  .ttitle { font-family: var(--mono); font-size: 12px; font-weight: 700; color: #e8e8e8; }
  .tstatus { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--m40); }
  .tstatus.ok { color: var(--green); }
  .tstatus.no { color: #ff6b6b; }
  .tspace { flex: 1; }
  .tbtn { background: none; border: 1px solid #3a3a3a; color: #cfcfcf; font-family: var(--mono); font-size: 11px; padding: 5px 11px; }
  .tbtn:hover { border-color: var(--green); color: var(--green); }
  .term { flex: 1; min-height: 0; padding: 8px 10px; overflow: hidden; }
  .term.away { display: none; }
  /* The message sits on a plain panel in the middle of the window, in the panel's usual light colours. */
  .notice { margin: auto; width: min(560px, calc(100% - 32px)); padding: 20px 22px; display: grid; gap: 14px; background: var(--white); color: var(--black); border: 1px solid var(--gray); }
  .ntext { margin: 0; font-size: 15px; }
  .nact { display: flex; gap: 8px; flex-wrap: wrap; }
  .term :global(.xterm) { height: 100%; }
  .term :global(.xterm-viewport) { overflow-y: auto; }
</style>
