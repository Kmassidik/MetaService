<script lang="ts">
  // AI access (MCP): connect an AI client, make and revoke its tokens, approve risky requests, see what it did.
  // While the Settings page is open it asks again every few seconds (and stops when the page closes), and redraws a list only when it changed.
  import { onMount } from 'svelte'
  import McpActivity from './McpActivity.svelte'
  import McpApprovals from './McpApprovals.svelte'
  import McpConnect from './McpConnect.svelte'
  import McpCreateDialog from './McpCreateDialog.svelte'
  import McpTokens from './McpTokens.svelte'
  import { ApiError, mcpActivity, mcpApprovals, mcpInfo, mcpTokens } from '../../lib/api.ts'
  import type { McpInfo, McpToken } from '../../lib/mcp.ts'
  import { listChanged, MCP_POLL_MS, shouldPollMcp, signatureOf } from '../../lib/mcpPoll.ts'
  import type { ActivityRow, Approvals } from '../../lib/mcpRequests.ts'
  import { NOT_AVAILABLE_TEXT } from '../../lib/mcpText.ts'

  const ACTIVITY_LIMIT = 20
  const NOT_FOUND = 404
  let info = $state<McpInfo | null>(null)
  let tokens = $state<McpToken[]>([])
  let approvals = $state<Approvals>({ pending: [], recent: [] })
  let activity = $state<ActivityRow[]>([])
  let signatures: Record<'tokens' | 'approvals' | 'activity', string | null> = { tokens: null, approvals: null, activity: null }
  let loaded = $state(false)
  let unavailable = $state(false)
  let failure = $state('')
  let creating = $state(false)
  let now = $state(Date.now())
  let reading = false

  /** Puts a list on screen only when it differs from the one shown. */
  function adopt<T>(name: keyof typeof signatures, next: T, put: (value: T) => void) {
    if (listChanged(signatures[name], next)) put(next)
    signatures[name] = signatureOf(next)
  }

  function fail(error: unknown) {
    unavailable = error instanceof ApiError && error.status === NOT_FOUND
    failure = unavailable ? '' : error instanceof ApiError ? error.message : 'Something went wrong.'
  }

  async function refresh() {
    if (reading) return
    reading = true
    try {
      const [facts, list, asks, calls] = await Promise.all([info ?? mcpInfo(), mcpTokens(), mcpApprovals(), mcpActivity(ACTIVITY_LIMIT)])
      info = facts
      adopt('tokens', list, (value) => (tokens = value))
      adopt('approvals', asks, (value) => (approvals = value))
      adopt('activity', calls, (value) => (activity = value))
      unavailable = false
      failure = ''
    } catch (error) {
      fail(error)
    } finally {
      reading = false
      now = Date.now()
      loaded = true
    }
  }

  const tick = () => shouldPollMcp({ hidden: document.hidden, unavailable }) && refresh()

  onMount(() => {
    void refresh()
    const timer = setInterval(tick, MCP_POLL_MS)
    document.addEventListener('visibilitychange', tick)
    return () => {
      clearInterval(timer)
      document.removeEventListener('visibilitychange', tick)
    }
  })
</script>

<section class="mcp" aria-label="AI access (MCP)" data-testid="mcp-section">
  <h2>AI access (MCP)</h2>
  {#if !loaded}
    <p class="muted" role="status" data-testid="mcp-loading">Reading AI access…</p>
  {:else if unavailable}
    <p class="muted" role="status" data-testid="mcp-unavailable">{NOT_AVAILABLE_TEXT}</p>
  {:else if !info}
    <div class="bad" role="alert" data-testid="mcp-failure">
      <p>{failure}</p>
      <button class="btn line sm" type="button" onclick={refresh}>Try again</button>
    </div>
  {:else}
    <p class="muted">Let an AI client such as Claude Code create and manage VMs here. It gets its own token, limits you set, and asks you before anything risky.</p>
    {#if failure}<p class="banner" role="alert" data-testid="mcp-banner">{failure}</p>{/if}
    <h3>Connect</h3>
    <McpConnect {info} />
    <h3>Tokens</h3>
    <McpTokens {tokens} {now} onChanged={refresh} onCreate={() => (creating = true)} />
    <h3>Waiting for approval{approvals.pending.length > 0 ? ` (${approvals.pending.length})` : ''}</h3>
    <McpApprovals pending={approvals.pending} recent={approvals.recent} {now} onChanged={refresh} />
    <h3>Recent activity</h3>
    <McpActivity rows={activity} {now} />
  {/if}
  <McpCreateDialog open={creating} defaults={info?.defaults} onClose={() => (creating = false)} onCreated={refresh} />
</section>

<style>
  .mcp { display: grid; gap: 12px; }
  h2 { font-size: 16px; }
  p { margin: 0; }
  .muted { color: var(--m60); font-size: 13px; line-height: 1.6; }
  .bad { display: grid; gap: 10px; justify-items: start; color: var(--danger-d); font-size: 13px; }
  .banner { margin: 0; }
</style>
