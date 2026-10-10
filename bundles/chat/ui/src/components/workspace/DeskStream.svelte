<script>
  import DeskPulse from './DeskPulse.svelte'

  // fullScreen: Esc is the way out of full screen there, so it keeps the desktop focused (control stays).
  let { src = '', reconnecting = false, fullScreen = false, onEscape, onActivity } = $props()

  // Contract with public/novnc/index.html: it posts { source, state } to its parent when the socket opens or drops.
  const DESKTOP_MESSAGE_SOURCE = 'ruvio-desktop'
  const DESKTOP_DROPPED = 'disconnected'
  // The pointer moved over the desktop; the iframe keeps those events from reaching Chat.
  const DESKTOP_ACTIVE = 'active'
  const RECONNECT_DELAY_MS = 2000

  let frame = $state(null)
  let focused = $state(false)
  let dropped = $state(false)
  let attempt = $state(0)
  let retryTimer

  const showReconnecting = $derived(reconnecting || dropped)

  // Keys typed into the desktop never reach Chat, so Esc is caught inside the same-origin viewer page.
  function listenForEscape() {
    if (!frame?.contentDocument) return
    frame.contentWindow.addEventListener('keydown', escapeToChat)
  }

  function escapeToChat(event) {
    if (event.key !== 'Escape') return
    event.preventDefault()
    if (fullScreen) return onEscape?.()
    frame.blur()
    focused = false
    onEscape?.()
  }

  function onDesktopMessage(event) {
    if (event.origin !== location.origin || event.source !== frame?.contentWindow) return
    if (event.data?.source !== DESKTOP_MESSAGE_SOURCE) return
    if (event.data.state === DESKTOP_ACTIVE) return onActivity?.()
    dropped = event.data.state === DESKTOP_DROPPED
    if (dropped) scheduleReconnect()
  }

  function scheduleReconnect() {
    clearTimeout(retryTimer)
    retryTimer = setTimeout(() => { attempt += 1 }, RECONNECT_DELAY_MS)
  }

  function focusHint() {
    if (!focused) return 'Click the desktop to control it'
    return fullScreen ? 'Esc exits full screen' : 'Esc returns to chat'
  }

  $effect(() => () => clearTimeout(retryTimer))
</script>

<svelte:window onmessage={onDesktopMessage} />

<div class="desk-stream" class:is-focused={focused}>
  {#key attempt}
    <iframe
      bind:this={frame}
      title="Live remote desktop"
      {src}
      allow="clipboard-read; clipboard-write"
      onload={listenForEscape}
      onfocus={() => { focused = true }}
      onblur={() => { focused = false }}
    ></iframe>
  {/key}
  {#if showReconnecting}
    <div class="desk-stream-overlay" role="status"><DeskPulse />Reconnecting…</div>
  {:else}
    <p class="desk-stream-hint" aria-live="polite">{focusHint()}</p>
  {/if}
</div>

<style>
  .desk-stream { position: relative; flex: 1; min-height: 0; display: flex; background: var(--stream-bg); }
  .desk-stream iframe { flex: 1; width: 100%; height: 100%; border: 0; background: var(--stream-bg); }
  .desk-stream.is-focused::after {
    content: '';
    position: absolute;
    inset: 0;
    border: 2px solid var(--brand-green);
    pointer-events: none;
  }
  .desk-stream-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 14px;
    background: color-mix(in srgb, var(--stream-bg) 72%, transparent);
    color: var(--on-stream);
    font: 500 var(--fs-name)/1.4 var(--font);
    backdrop-filter: blur(2px);
  }
  .desk-stream-hint {
    position: absolute;
    left: 50%;
    bottom: 12px;
    transform: translateX(-50%);
    padding: 5px 11px;
    border-radius: var(--radius-pill);
    background: var(--tooltip-bg);
    color: var(--tooltip-text);
    font: 500 var(--fs-time)/1.2 var(--font);
    white-space: nowrap;
    pointer-events: none;
    opacity: .85;
  }
</style>
