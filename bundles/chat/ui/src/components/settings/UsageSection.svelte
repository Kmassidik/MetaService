<script>
  /** Settings › Usage & plan: allowance left, tokens this month, and the plan's bot and group limits. */
  import Icon from '../Icon.svelte'
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import { chat, loadUsage } from '../../lib/chatApp.svelte.js'
  import { MAX_GROUP_CHATS, ICON_SIZE } from '../../lib/constants.js'
  import { number } from '../../lib/format.js'

  const PLAN_NAME = 'Invite beta'

  let { view } = $props()

  const usage = $derived(chat.usage)
  const remaining = $derived(Math.max(0, Number(usage?.remaining || 0)))
  const allowance = $derived(Math.max(0, Number(usage?.tokens || 0) + remaining))
  const allowanceText = $derived(allowance > 0 ? `${number(remaining)} of ${number(allowance)} tokens left` : `${number(remaining)} tokens left`)
</script>

{#snippet refresh()}
  <button class="icon-button" aria-label="Refresh usage" disabled={chat.deletingAccount} onclick={loadUsage}><Icon name="refresh" size={ICON_SIZE.inline} /></button>
{/snippet}

<SettingsGroup title="Allowance" action={refresh}>
  <div class="allowance">
    <div class="allowance-line"><span>Allowance left</span><span class="value">{usage ? allowanceText : '—'}</span></div>
    {#if allowance > 0}<progress class="meter-bar" aria-label="Allowance remaining" value={remaining} max={allowance}></progress>{/if}
  </div>
  <SettingsRow label="Tokens this month" value={number(usage?.monthly?.tokens)} />
</SettingsGroup>
{#if usage?.blocked}<div class="error-box">Your free allowance is used up for now.</div>{/if}
{#if chat.usageError}<div class="error-box" role="alert">{chat.usageError}</div>{/if}

<SettingsGroup title="Plan">
  <SettingsRow label="Plan" value={PLAN_NAME} />
  {#if view.planLimits}
    <SettingsRow label="Bots" value={`${view.bots.length} of ${view.planLimits.maxAgents}`} />
    <SettingsRow label="Group chats" value={`${view.teams.length} of ${MAX_GROUP_CHATS}`} />
  {/if}
</SettingsGroup>

<style>
  .allowance { padding: 12px 14px; }
  .allowance-line { display: flex; justify-content: space-between; gap: 12px; font: 400 var(--fs-menu)/1.35 var(--font); }
  .value { color: var(--text-2); text-align: right; }
  .meter-bar { margin-top: 9px; }
</style>
