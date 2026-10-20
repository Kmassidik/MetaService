<script lang="ts">
  import { onMount } from 'svelte'
  import { parseConfig } from '../../lib/answers/account.ts'
  const REQUEST_TIMEOUT_MS = 8000
  const RECHECK_INTERVAL_MS = 15000
  type Status = 'checking' | 'connected' | 'reconnecting' | 'offline'

  let status = $state<Status>('checking')
  let checkedAt = $state('')
  const labels: Record<Status, string> = { checking: 'Checking connection', connected: 'Workspace reachable', reconnecting: 'Reconnecting', offline: 'Offline' }
  onMount(() => {
    let controller: AbortController | undefined
    let timer: ReturnType<typeof setTimeout> | undefined
    let stopped = false
    async function check(): Promise<void> {
      clearTimeout(timer)
      controller?.abort()
      if (!navigator.onLine) { status = 'offline'; return }
      const request = new AbortController()
      controller = request
      const deadline = setTimeout(() => request.abort(), REQUEST_TIMEOUT_MS)
      try {
        const response = await fetch('/api/config', { signal: request.signal, cache: 'no-store', credentials: 'same-origin' })
        if (!response.ok) throw new Error('Unavailable')
        parseConfig(await response.json())
        if (!stopped && controller === request) { status = 'connected'; checkedAt = new Date().toLocaleTimeString() }
      } catch {
        if (!stopped && controller === request) status = navigator.onLine ? 'reconnecting' : 'offline'
      } finally {
        clearTimeout(deadline)
        if (!stopped && controller === request) timer = setTimeout(check, RECHECK_INTERVAL_MS)
      }
    }
    function online(): void { status = 'checking'; check() }
    function offline(): void { controller?.abort(); clearTimeout(timer); status = 'offline' }
    function visible(): void { if (!document.hidden) online() }
    window.addEventListener('online', online)
    window.addEventListener('offline', offline)
    document.addEventListener('visibilitychange', visible)
    check()
    return () => { stopped = true; controller?.abort(); clearTimeout(timer); window.removeEventListener('online', online); window.removeEventListener('offline', offline); document.removeEventListener('visibilitychange', visible) }
  })
</script>

<div class="connection-status" class:connected={status === 'connected'} role="status" title={`Checks workspace reachability, not model or computer health.${checkedAt ? ` Last success: ${checkedAt}.` : ''}`}><span aria-hidden="true"></span>{labels[status]}</div>

<style>
  .connection-status { display: flex; align-items: center; gap: 8px; margin: 0 6px 10px; color: var(--text-2); font: 500 13px/1.3 var(--font); }
  .connection-status span { width: 7px; height: 7px; border-radius: var(--radius-avatar); background: var(--warn-text); flex-shrink: 0; }
  .connected span { background: var(--ok); }
</style>
