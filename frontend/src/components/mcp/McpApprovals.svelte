<script lang="ts">
  // Waiting for approval: each request in plain words with Approve and Deny, and the ones decided lately below. Names are text only.
  import ActionButton from '../ActionButton.svelte'
  import { mcpApprove, mcpDeny } from '../../lib/api.ts'
  import type { McpRequest } from '../../lib/mcpRequests.ts'
  import { wantsText, stateWords } from '../../lib/mcpRequestText.ts'
  import { agoText } from '../../lib/mcpText.ts'

  let { pending, recent, now, onChanged }: { pending: McpRequest[]; recent: McpRequest[]; now: number; onChanged: () => Promise<void> } = $props()

  async function decide(work: Promise<unknown>) {
    await work
    await onChanged()
  }
</script>

{#if pending.length === 0}
  <p class="none" data-testid="mcp-approvals-empty">Nothing is waiting. A risky request from an AI client shows up here.</p>
{:else}
  <ul class="asks" data-testid="mcp-pending">
    {#each pending as ask (ask.id)}
      <li>
        <p class="what" data-testid="ask-text"><strong>{ask.tokenName}</strong> wants to {wantsText(ask)}</p>
        <p class="small">asked {agoText(ask.createdAt, now)}</p>
        <div class="acts">
          <ActionButton label="Approve" busyLabel="Approving…" doneLabel="Approved" variant="green" small onrun={() => decide(mcpApprove(ask.id))} />
          <ActionButton label="Deny" busyLabel="Denying…" doneLabel="Denied" variant="danger" small onrun={() => decide(mcpDeny(ask.id))} />
        </div>
      </li>
    {/each}
  </ul>
{/if}
{#if recent.length > 0}
  <h4>Decided lately</h4>
  <ul class="done" data-testid="mcp-decided">
    {#each recent as ask (ask.id)}
      <li><span><strong>{ask.tokenName}</strong> wanted to {wantsText(ask)}</span> <span class="small">{stateWords(ask.state)}{ask.decidedBy ? ` by ${ask.decidedBy}` : ''}{ask.decidedAt !== null ? `, ${agoText(ask.decidedAt, now)}` : ''}</span></li>
    {/each}
  </ul>
{/if}

<style>
  .none { margin: 0; color: var(--m50); font-size: 13px; }
  ul { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); }
  li { padding: 12px 16px; border-top: 1px solid var(--line); display: grid; gap: 6px; font-size: 13px; overflow-wrap: anywhere; }
  li:first-child { border-top: 0; }
  p { margin: 0; }
  .what { line-height: 1.6; }
  .small { font-family: var(--mono); font-size: 11px; color: var(--m50); }
  .acts { display: flex; gap: 8px; flex-wrap: wrap; align-items: flex-start; }
  h4 { margin: 8px 0 0; font-family: var(--mono); font-size: 11px; letter-spacing: .1em; text-transform: uppercase; color: var(--m50); }
  .done li { color: var(--m70); }
</style>
