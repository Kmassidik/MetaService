<script>
  /**
   * The sidebar + menu: new bot or new group chat. Limits and storage problems show here as the
   * reason an item is disabled, instead of as notices in the sidebar.
   */
  import Icon from '../Icon.svelte'
  import FloatingMenu from './FloatingMenu.svelte'
  import { GROUP_LIMIT_REASON, botLimitReason } from '../../lib/constants.js'

  let {
    open = false,
    x = 0,
    y = 0,
    saving = false,
    storageBlockedReason = '',
    agentLimitReached = false,
    maxBots = 0,
    teamLimitReached = false,
    createTeamBlocked = false,
    readyBotCount = 0,
    onNewBot,
    onNewGroup,
    onRefreshStorage,
    onManageStorage,
    onOpenUsage,
    onClose,
  } = $props()

  const MIN_GROUP_BOTS = 2
  const STORAGE_CHECKING = 'Checking storage…'
  const NEEDS_BOTS_REASON = `Needs ${MIN_GROUP_BOTS} ready bots.`
  const NEEDS_STORAGE_REASON = 'Needs available storage.'

  function groupBlockedReason() {
    if (!createTeamBlocked) return ''
    if (teamLimitReached) return GROUP_LIMIT_REASON
    if (readyBotCount < MIN_GROUP_BOTS) return NEEDS_BOTS_REASON
    return storageBlockedReason ? NEEDS_STORAGE_REASON : STORAGE_CHECKING
  }

  // Storage is re-checked inside the create flow, so only the hard bot limit disables New bot.
  const botReason = $derived(agentLimitReached ? botLimitReason(maxBots) : '')
  const groupReason = $derived(groupBlockedReason())

  function choose(action) {
    onClose?.()
    action?.()
  }
</script>

<FloatingMenu {open} {x} {y} label="New chat" {onClose}>
  <button type="button" role="menuitem" class="menu-item" disabled={saving || Boolean(botReason)} onclick={() => choose(onNewBot)}><Icon name="spark" size={17} />New bot</button>
  {#if botReason}
    <p class="menu-note">{botReason} <button type="button" class="note-link" onclick={() => choose(onOpenUsage)}>See usage in Settings</button></p>
  {/if}
  <button type="button" role="menuitem" class="menu-item" disabled={saving || Boolean(groupReason)} onclick={() => choose(onNewGroup)}><Icon name="team" size={17} />New group chat</button>
  {#if groupReason}<p class="menu-note">{groupReason}</p>{/if}
  {#if storageBlockedReason}
    <hr class="menu-divider" />
    <p class="menu-note">{storageBlockedReason}</p>
    <button type="button" role="menuitem" class="menu-item" onclick={() => choose(onRefreshStorage)}><Icon name="refresh" size={17} />Refresh storage</button>
    <button type="button" role="menuitem" class="menu-item" onclick={() => choose(onManageStorage)}><Icon name="settings" size={17} />Manage storage</button>
  {/if}
</FloatingMenu>

<style>
  .note-link { padding: 0; border: 0; background: none; color: var(--text); font: 500 var(--fs-preview)/1.35 var(--font); text-decoration: underline; text-underline-offset: 3px; cursor: pointer; }
</style>
