<script lang="ts">
  // The web terminal of one running VM: a modal with xterm, joined to the VM's shell through the Root. Same look and behaviour as the MAAS Terminal.
  // Every connection (the first and each Reconnect) asks the Root for a new one-use ticket.
  import { onMount } from 'svelte'
  import { Terminal } from '@xterm/xterm'
  import { FitAddon } from '@xterm/addon-fit'
  import '@xterm/xterm/css/xterm.css'
  import { ApiError, openTerminal } from '../lib/api.ts'
  import { isDead, isLive, nextState, resizeMessage, roundBox, shouldRefit, SOCKET_OPEN, statusText, statusTone, terminalSocketUrl } from '../lib/terminal.ts'
  import type { Box, TerminalEvent, TerminalState } from '../lib/terminal.ts'

  interface Props {
    machine: string
    workload: string
    /** The VM's name in the title. */
    name: string
    onclose: () => void
  }

  const FIRST_FIT_DELAY_MS = 50
  const ACCENT_TOKEN = '--accent'
  const accentColour = () => getComputedStyle(document.documentElement).getPropertyValue(ACCENT_TOKEN).trim()
  /** The terminal keeps its own dark colours in every theme. Only the cursor and the selection take the panel's accent colour, read from its token. */
  const terminalOptions = () => ({
    cursorBlink: true,
    fontFamily: "'Space Mono',ui-monospace,monospace",
    fontSize: 13,
    scrollback: 5000,
    theme: { background: '#111111', foreground: '#e8e8e8', cursor: accentColour(), selectionBackground: accentColour(), selectionForeground: '#111111' },
  })

  let { machine, workload, name, onclose }: Props = $props()
  let host: HTMLDivElement | undefined
  let phase: TerminalState = $state('connecting')
  let reason = $state('')
  const term = new Terminal(terminalOptions())
  const fit = new FitAddon()
  let socket: WebSocket | undefined
  let asking = false
  let disposed = false

  const text = $derived(statusText(phase, reason))
  const tone = $derived(statusTone(phase))
  const dead = $derived(isDead(phase))

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
      reason = event.reason
      happened('close')
    }
    socket = ws
  }

  function failed(error: unknown) {
    reason = error instanceof ApiError ? error.message : 'Cannot reach the Root.'
    happened('error')
  }

  /** A new ticket, then a new socket. Does nothing while one is already being asked for, opening or open. */
  async function connect() {
    if (asking || (socket && isLive(socket.readyState))) return
    asking = true
    reason = ''
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
      {#if dead}<button class="tbtn" type="button" onclick={() => void connect()}>Reconnect</button>{/if}
      <button class="tbtn" type="button" onclick={onclose} aria-label="Close terminal">✕ Close</button>
    </div>
    <div class="term" bind:this={host}></div>
  </div>
</div>

<style>
  /* fills most of the viewport; the terminal itself flexes to fill all space below the header */
  .term-box { width: min(1000px, 96vw); height: 82vh; display: flex; flex-direction: column; background: var(--term-bg); border-color: var(--term-line); }
  .thead { flex-shrink: 0; display: flex; align-items: center; gap: 12px; padding: 9px 14px; background: var(--term-bar); border-bottom: 1px solid var(--term-line); }
  .ttitle { font-family: var(--mono); font-size: 12px; font-weight: 700; color: var(--term-text); }
  .tstatus { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--m40); }
  .tstatus.ok { color: var(--accent); }
  .tstatus.no { color: var(--term-bad); }
  .tspace { flex: 1; }
  .tbtn { background: none; border: 1px solid var(--term-button-line); color: var(--term-button-text); font-family: var(--mono); font-size: 11px; padding: 5px 11px; }
  .tbtn:hover { border-color: var(--accent); color: var(--accent); }
  .term { flex: 1; min-height: 0; padding: 8px 10px; overflow: hidden; }
  .term :global(.xterm) { height: 100%; }
  .term :global(.xterm-viewport) { overflow-y: auto; }
</style>
