<script>
  /** Account menu from the sidebar avatar: usage, Settings, Help, Log out. */
  import Icon from '../Icon.svelte'
  import FloatingMenu from './FloatingMenu.svelte'

  let {
    open = false,
    x = 0,
    y = 0,
    userName = '',
    userEmail = '',
    usage = null,
    loggingOut = false,
    onUsage,
    onSettings,
    onHelp,
    onLogout,
    onClose,
  } = $props()

  const PERCENT = 100

  /** Share of the allowance used so far; null when the allowance isn't known yet. */
  function usedPercent(value) {
    const used = Math.max(0, Number(value?.tokens || 0))
    const allowance = used + Math.max(0, Number(value?.remaining || 0))
    if (!allowance) return null
    return Math.min(PERCENT, Math.round((used / allowance) * PERCENT))
  }

  const percent = $derived(usedPercent(usage))

  function choose(action) {
    onClose?.()
    action?.()
  }
</script>

<FloatingMenu {open} {x} {y} placement="up" label="Account" {onClose}>
  <div class="account-identity">
    <span class="account-name">{userName}</span>
    {#if userEmail}<span class="account-email">{userEmail}</span>{/if}
  </div>
  <button type="button" role="menuitem" class="menu-item" onclick={() => choose(onUsage)}>
    <Icon name="activity" size={17} />Usage
    <span class="menu-item-trail">{percent === null ? '' : `${percent}%`}</span>
    <Icon name="chevron" size={15} />
  </button>
  <button type="button" role="menuitem" class="menu-item" onclick={() => choose(onSettings)}><Icon name="settings" size={17} />Settings</button>
  <button type="button" role="menuitem" class="menu-item" onclick={() => choose(onHelp)}><Icon name="info" size={17} />Help</button>
  <hr class="menu-divider" />
  <button type="button" role="menuitem" class="menu-item" disabled={loggingOut || !onLogout} onclick={() => choose(onLogout)}><Icon name="logout" size={17} />{loggingOut ? 'Logging out…' : 'Log out'}</button>
</FloatingMenu>

<style>
  .account-identity { display: flex; flex-direction: column; gap: 2px; padding: 8px 10px 10px; }
  .account-name { color: var(--text); font: 500 var(--fs-name)/1.3 var(--font); }
  .account-email { color: var(--text-2); font: 400 var(--fs-preview)/1.3 var(--font); overflow-wrap: anywhere; }
</style>
