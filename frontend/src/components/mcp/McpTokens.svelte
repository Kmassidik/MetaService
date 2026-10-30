<script lang="ts">
  // The tokens: a table, Revoke with a confirm, and the button that opens the Create token window. Names are typed by people: shown as text only.
  import ConfirmDialog from '../ConfirmDialog.svelte'
  import { mcpRevokeToken } from '../../lib/api.ts'
  import type { McpToken } from '../../lib/mcp.ts'
  import { expiryText, isLive, lastUsedText, quotaLine, revokeCopy, SCOPE_TEXT } from '../../lib/mcpText.ts'

  let { tokens, now, onChanged, onCreate }: { tokens: McpToken[]; now: number; onChanged: () => Promise<void>; onCreate: () => void } = $props()
  let revoking = $state<McpToken | null>(null)
  const copy = $derived(revokeCopy(revoking ?? { name: '' }))

  async function revoke() {
    if (!revoking) return
    await mcpRevokeToken(revoking.id)
    await onChanged()
  }
</script>

<div class="bar"><button class="btn green sm" type="button" onclick={onCreate}>Create token</button></div>
{#if tokens.length === 0}
  <p class="none" data-testid="mcp-tokens-empty">No tokens yet. Make one to let an AI client connect.</p>
{:else}
  <div class="tablewrap">
    <table class="restable stack" data-testid="mcp-tokens">
      <thead><tr><th>Name</th><th>Prefix</th><th>Can do</th><th>Limits</th><th>Last used</th><th>Expires</th><th><span class="sr">Actions</span></th></tr></thead>
      <tbody>
        {#each tokens as token (token.id)}
          <tr class:gone={!isLive(token, now)}>
            <td class="c-name" data-label="Name" data-testid="token-name">{token.name}{#if token.autoApprove}<span class="tag warn auto">auto-approve</span>{/if}</td>
            <td class="small" data-label="Prefix">msk_{token.prefix}…</td>
            <td data-label="Can do"><span class="chips">{#each token.scopes as scope (scope)}<span class="tag" title={SCOPE_TEXT[scope].explain}>{scope}</span>{/each}</span></td>
            <td class="small" data-label="Limits">{quotaLine(token.quotas, token.scopes)}</td>
            <td data-label="Last used">{lastUsedText(token.lastUsedAt, now)}</td>
            <td data-label="Expires">{expiryText(token, now)}</td>
            <td data-label="">{#if token.revokedAt === null}<button class="btn danger sm" type="button" aria-label="Revoke {token.name}" onclick={() => (revoking = token)}>Revoke</button>{/if}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<ConfirmDialog open={revoking !== null} {...copy} onconfirm={revoke} onClose={() => (revoking = null)} />

<style>
  .bar { display: flex; justify-content: flex-end; }
  .none { margin: 0; color: var(--m50); font-size: 13px; }
  .tablewrap { padding: 0; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); overflow-wrap: anywhere; }
  .chips { display: flex; gap: 4px; flex-wrap: wrap; }
  .auto { margin-left: 8px; }
  .gone { opacity: .55; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
</style>
