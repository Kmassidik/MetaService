<script lang="ts">
  // AI access (MCP): connect an AI client, add the people who use it, make and revoke their tokens, see what they did.
  // While the AI access page is open it asks again every few seconds (and stops when the page closes), and redraws a list only when it changed.
  import { onMount } from 'svelte'
  import McpActivity from './McpActivity.svelte'
  import McpConnect from './McpConnect.svelte'
  import McpCreateDialog from './McpCreateDialog.svelte'
  import McpPeople from './McpPeople.svelte'
  import McpPersonDialog from './McpPersonDialog.svelte'
  import McpTokens from './McpTokens.svelte'
  import { ApiError, mcpActivity, mcpInfo, mcpPeople, mcpTokens } from '../../lib/api.ts'
  import type { McpInfo, McpPerson, McpToken } from '../../lib/mcp.ts'
  import { listChanged, MCP_POLL_MS, shouldPollMcp, signatureOf } from '../../lib/mcpPoll.ts'
  import type { ActivityRow } from '../../lib/mcpActivity.ts'
  import { NOT_AVAILABLE_TEXT } from '../../lib/mcpText.ts'

  const ACTIVITY_LIMIT = 20
  const NOT_FOUND = 404
  let info = $state<McpInfo | null>(null)
  let tokens = $state<McpToken[]>([])
  let people = $state<McpPerson[]>([])
  let activity = $state<ActivityRow[]>([])
  let signatures: Record<'tokens' | 'people' | 'activity', string | null> = { tokens: null, people: null, activity: null }
  let loaded = $state(false)
  let unavailable = $state(false)
  let failure = $state('')
  let creating = $state(false)
  /** The person window: closed, adding (person null) or editing. */
  let personDialog = $state<{ person: McpPerson | null } | null>(null)
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
      const [facts, crowd, list, calls] = await Promise.all([info ?? mcpInfo(), mcpPeople(), mcpTokens(), mcpActivity(ACTIVITY_LIMIT)])
      info = facts
      adopt('people', crowd, (value) => (people = value))
      adopt('tokens', list, (value) => (tokens = value))
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
    <p class="muted">Let people use an AI client such as Claude Code to create and manage VMs here. Each person has limits you set and their own tokens. Every VM keeps a record of who made it.</p>
    {#if failure}<p class="banner" role="alert" data-testid="mcp-banner">{failure}</p>{/if}
    <h3>Connect</h3>
    <McpConnect {info} />
    <h3>People</h3>
    <McpPeople {people} {now} onChanged={refresh} onAdd={() => (personDialog = { person: null })} onEdit={(person) => (personDialog = { person })} />
    <h3>Tokens</h3>
    <McpTokens {tokens} {now} onChanged={refresh} onCreate={() => (creating = true)} />
    <h3>Recent activity</h3>
    <McpActivity rows={activity} {now} />
  {/if}
  <McpPersonDialog open={personDialog !== null} person={personDialog?.person ?? null} defaults={info?.defaults} onClose={() => (personDialog = null)} onSaved={refresh} />
  <McpCreateDialog open={creating} {people} defaults={info?.defaults} onClose={() => (creating = false)} onCreated={refresh} />
</section>

<style>
  .mcp { display: grid; gap: 12px; }
  p { margin: 0; }
  .muted { color: var(--m60); font-size: 13px; line-height: 1.6; }
  .bad { display: grid; gap: 10px; justify-items: start; color: var(--danger-d); font-size: 13px; }
  .banner { margin: 0; }
</style>
