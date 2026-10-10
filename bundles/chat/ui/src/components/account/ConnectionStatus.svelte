<script>
  import { onMount } from 'svelte'
  const REQUEST_TIMEOUT_MS = 8000
  const RECHECK_INTERVAL_MS = 15000
  let state = $state('checking')
  let checkedAt = $state('')
  const labels = { checking: 'Checking connection', connected: 'Workspace reachable', reconnecting: 'Reconnecting', offline: 'Offline' }
  onMount(() => {
    let controller
    let timer
    let stopped = false
    async function check() {
      clearTimeout(timer)
      controller?.abort()
      if (!navigator.onLine) { state = 'offline'; return }
      const request = new AbortController()
      controller = request
      const deadline = setTimeout(() => request.abort(), REQUEST_TIMEOUT_MS)
      try {
        const response = await fetch('/api/config', { signal: request.signal, cache: 'no-store', credentials: 'same-origin' })
        const data = await response.json()
        if (!response.ok || typeof data.googleConfigured !== 'boolean') throw new Error('Unavailable')
        if (!stopped && controller === request) { state = 'connected'; checkedAt = new Date().toLocaleTimeString() }
      } catch {
        if (!stopped && controller === request) state = navigator.onLine ? 'reconnecting' : 'offline'
      } finally {
        clearTimeout(deadline)
        if (!stopped && controller === request) timer = setTimeout(check, RECHECK_INTERVAL_MS)
      }
    }
    function online() { state = 'checking'; check() }
    function offline() { controller?.abort(); clearTimeout(timer); state = 'offline' }
    function visible() { if (!document.hidden) online() }
    window.addEventListener('online', online)
    window.addEventListener('offline', offline)
    document.addEventListener('visibilitychange', visible)
    check()
    return () => { stopped = true; controller?.abort(); clearTimeout(timer); window.removeEventListener('online', online); window.removeEventListener('offline', offline); document.removeEventListener('visibilitychange', visible) }
  })
</script>

<div class="connection-status" class:connected={state === 'connected'} role="status" title={`Checks workspace reachability, not model or computer health.${checkedAt ? ` Last success: ${checkedAt}.` : ''}`}><span aria-hidden="true"></span>{labels[state]}</div>

<style>
  .connection-status { display: flex; align-items: center; gap: 8px; margin: 0 6px 10px; color: var(--text-2); font: 500 13px/1.3 var(--font); }
  .connection-status span { width: 7px; height: 7px; border-radius: var(--radius-avatar); background: var(--warn-text); flex-shrink: 0; }
  .connected span { background: var(--ok); }
</style>
