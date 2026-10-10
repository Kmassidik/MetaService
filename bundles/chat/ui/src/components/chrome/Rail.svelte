<script>
  /**
   * Sidebar: search and + at the top, one merged list of bots and group
   * chats, then the account avatar and the Connect apps pill. Notices live in menus, not here.
   */
  import Icon from '../Icon.svelte'
  import RosterRow from './RosterRow.svelte'
  import BotContextMenu from './BotContextMenu.svelte'
  import NewChatMenu from './NewChatMenu.svelte'
  import AccountMenu from './AccountMenu.svelte'
  import AvatarPickerPopover from './AvatarPickerPopover.svelte'
  import UserAvatar from '../UserAvatar.svelte'
  import { DRAWER_MAX_WIDTH, MODALS } from '../../lib/constants.js'
  import { SETTINGS } from '../../lib/settingsSections.js'
  import { buildRoster, groupFaces, hiddenRoster, isBusy, rowPreview, unreadLabel } from '../../lib/chat/roster.js'

  let {
    mobileRail = false,
    search = $bindable(''),
    showHidden = false,
    selectedId = '',
    pending = null,
    bots = [],
    teams = [],
    readyBots = [],
    activityAt = {},
    createTeamBlocked = false,
    teamLimitReached = false,
    agentLimitReached = false,
    storageBlocked = false,
    storage = null,
    storageError = '',
    agentsError = '',
    saving = false,
    usage = null,
    loggingOut = false,
    session,
    selectAgent,
    loadStorage,
    loadAgents,
    openModal,
    openProfile,
    patchRoster,
    duplicateAgent,
    onCloseMobile,
    onToggleHidden,
    onNewBot,
    onLogout,
  } = $props()

  const MENU_GAP = 6
  const CLOSED = { open: false, x: 0, y: 0, agent: null }
  // ⌘/Ctrl+N makes a New bot on desktop; the phone drawer has no keyboard shortcut.
  const NEW_BOT_KEY = 'n'
  const DESKTOP_QUERY = `(min-width: ${DRAWER_MAX_WIDTH + 1}px)`

  let menu = $state(CLOSED)
  let avatarPicker = $state(CLOSED)
  let newMenu = $state(CLOSED)
  let accountMenu = $state(CLOSED)
  let searchOpen = $state(false)
  let newButton = $state(null)

  const allAgents = $derived([...bots, ...teams])
  const roster = $derived(buildRoster(allAgents, { query: search, activityAt }))
  const hidden = $derived(hiddenRoster(bots))
  const storageReason = $derived(storageBlocked || storageError ? storage?.creationBlockedReason || storageError : '')

  function closeMenus() {
    menu = CLOSED
    avatarPicker = CLOSED
  }

  function below(button) {
    const rect = button.getBoundingClientRect()
    return { open: true, x: rect.left, y: rect.bottom + MENU_GAP, agent: null }
  }

  function isNewBotShortcut(event) {
    const modifier = event.metaKey || event.ctrlKey
    return modifier && !event.shiftKey && !event.altKey && event.key.toLowerCase() === NEW_BOT_KEY
  }

  // At the bot limit the shortcut opens the + menu, which says why and links to usage.
  function onShortcut(event) {
    if (!isNewBotShortcut(event) || !window.matchMedia(DESKTOP_QUERY).matches) return
    event.preventDefault()
    if (!agentLimitReached) { onNewBot(); return }
    newMenu = below(newButton)
  }

  function aboveButton(event) {
    const rect = event.currentTarget.getBoundingClientRect()
    return { open: true, x: rect.left, y: rect.top - MENU_GAP, agent: null }
  }

  function openRowMenu(agent, point) {
    avatarPicker = CLOSED
    menu = { open: true, ...point, agent }
  }

  function openAvatarPicker(agent, point) {
    menu = CLOSED
    avatarPicker = { open: true, ...point, agent }
  }

  function openAvatarBelow(agent, point) {
    openAvatarPicker(agent, { x: point.x, y: point.y + MENU_GAP })
  }

  function toggleSearch() {
    searchOpen = !searchOpen
    if (!searchOpen) search = ''
  }

  function onSearchKey(event) {
    if (event.key !== 'Escape') return
    search = ''
    searchOpen = false
  }

  function focusOnMount(node) {
    node.focus()
  }

  async function showDetails(agent) {
    await selectAgent(agent.id)
    await openProfile()
  }

  const MENU_ACTIONS = {
    avatar: agent => openAvatarPicker(agent, { x: menu.x, y: menu.y }),
    pin: agent => patchRoster({ pinned: !agent.pinned }, agent.id),
    hide: agent => patchRoster({ hidden: !agent.hidden }, agent.id),
    duplicate: agent => duplicateAgent(agent.id),
    details: showDetails,
    delete: agent => openModal(MODALS.delete, agent.id),
  }

  async function onMenuAction(action, agent) {
    if (!agent) return
    await MENU_ACTIONS[action]?.(agent)
  }

  async function onAvatarPick(option) {
    const agent = avatarPicker.agent
    if (!agent) return
    await patchRoster({ avatarColor: option.color, avatarShape: option.shape }, agent.id)
  }
</script>

<svelte:window onkeydown={onShortcut} />

<aside id="bot-navigation" class="rail sidebar" class:mobile-open={mobileRail} aria-label="Your bots and group chats">
  <header class="sidebar-top">
    <button type="button" class="round-button mobile-only" aria-label="Close navigation" onclick={onCloseMobile}><Icon name="close" size={18} /></button>
    <span class="sidebar-wordmark">Ruvio</span>
    <button type="button" class="round-button" aria-label="Search bots and group chats" aria-pressed={searchOpen} onclick={toggleSearch}><Icon name="search" size={18} /></button>
    <button type="button" class="round-button" aria-label="New chat" aria-haspopup="menu" disabled={saving} bind:this={newButton} onclick={() => newMenu = below(newButton)}><Icon name="plus" size={18} /></button>
  </header>

  {#if searchOpen}
    <label class="sidebar-search">
      <Icon name="search" size={15} />
      <input aria-label="Search bots and group chats" placeholder="Search" bind:value={search} onkeydown={onSearchKey} use:focusOnMount />
    </label>
  {/if}

  <nav class="sidebar-list" aria-label="Conversations">
    {#each roster as agent (agent.id)}
      <RosterRow
        {agent}
        faces={groupFaces(agent, bots)}
        preview={rowPreview(agent, pending)}
        unread={unreadLabel(agent, selectedId)}
        busy={isBusy(agent, pending)}
        selected={selectedId === agent.id}
        onSelect={() => selectAgent(agent.id)}
        onMenu={openRowMenu}
        onAvatar={openAvatarBelow}
      />
    {:else}
      <!-- With no bots the empty state in the chat area speaks; the list stays quiet. -->
      {#if search}<p class="sidebar-empty">No matches.</p>{/if}
    {/each}

    {#if hidden.length}
      <button type="button" class="sidebar-quiet-link" onclick={onToggleHidden}>{showHidden ? 'Hide hidden bots' : `Show ${hidden.length} hidden`}</button>
    {/if}
    {#if showHidden}
      {#each hidden as agent (agent.id)}
        <RosterRow {agent} preview={rowPreview(agent)} selected={selectedId === agent.id} onSelect={() => selectAgent(agent.id)} onMenu={openRowMenu} onAvatar={openAvatarBelow} />
      {/each}
    {/if}

    {#if agentsError}
      <div class="sidebar-error" role="alert">{agentsError}<button type="button" class="sidebar-quiet-link" onclick={loadAgents}>Reload conversations</button></div>
    {/if}
  </nav>

  <footer class="sidebar-bottom">
    <button type="button" class="account-avatar" aria-label={`Account: ${session.user.name}`} aria-haspopup="menu" onclick={event => accountMenu = aboveButton(event)}><UserAvatar user={session.user} class="account-avatar-face" /></button>
  </footer>
</aside>

<BotContextMenu open={menu.open} x={menu.x} y={menu.y} agent={menu.agent} {agentLimitReached} onAction={onMenuAction} onClose={() => menu = CLOSED} />
<AvatarPickerPopover open={avatarPicker.open} x={avatarPicker.x} y={avatarPicker.y} agent={avatarPicker.agent} onPick={onAvatarPick} onClose={closeMenus} />
<NewChatMenu
  open={newMenu.open}
  x={newMenu.x}
  y={newMenu.y}
  {saving}
  storageBlockedReason={storageReason}
  {agentLimitReached}
  {teamLimitReached}
  {createTeamBlocked}
  readyBotCount={readyBots.length}
  maxBots={session.limits?.maxAgents ?? 0}
  {onNewBot}
  onNewGroup={() => openModal(MODALS.createTeam)}
  onRefreshStorage={loadStorage}
  onManageStorage={() => openModal(MODALS.account, null, SETTINGS.computer)}
  onOpenUsage={() => openModal(MODALS.account, null, SETTINGS.usage)}
  onClose={() => newMenu = CLOSED}
/>
<AccountMenu
  open={accountMenu.open}
  x={accountMenu.x}
  y={accountMenu.y}
  userName={session.user.name}
  userEmail={session.user.email}
  {usage}
  {loggingOut}
  onUsage={() => openModal(MODALS.account, null, SETTINGS.usage)}
  onSettings={() => openModal(MODALS.account)}
  onHelp={() => openModal(MODALS.help)}
  {onLogout}
  onClose={() => accountMenu = CLOSED}
/>

<style>
  .sidebar { width: 100%; }
  .sidebar-top { display: flex; align-items: center; gap: 8px; flex-shrink: 0; padding: 14px 14px 8px; }
  .sidebar-wordmark { flex: 1; min-width: 0; padding-left: 6px; color: var(--text); font: 600 19px/1 var(--font); letter-spacing: -0.01em; }
  .round-button {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    padding: 0;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text);
    cursor: pointer;
  }
  .round-button:hover:not(:disabled), .round-button[aria-pressed='true'] { background: var(--row-hover); }
  .round-button:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  .round-button:disabled { color: var(--text-3); cursor: default; }
  /* Scoped display beats the global .mobile-only rule, so restate its breakpoint here. */
  .round-button.mobile-only { display: none; }
  @media (max-width: 820px) {
    .round-button.mobile-only { display: grid; }
  }
  .sidebar-search {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0 14px 8px;
    padding: 0 12px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-pill);
    background: var(--page);
    color: var(--text-2);
  }
  .sidebar-search input {
    flex: 1;
    min-width: 0;
    padding: 8px 0;
    border: 0;
    background: transparent;
    color: var(--text);
    font: 400 var(--fs-menu)/1.3 var(--font);
    outline: none;
  }
  .sidebar-list { flex: 1; min-height: 0; overflow-y: auto; padding: 4px 8px 12px; }
  .sidebar-empty { margin: 0; padding: 12px 10px; color: var(--text-2); font: 400 var(--fs-preview)/1.4 var(--font); }
  .sidebar-quiet-link {
    display: block;
    margin: 6px 10px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--text-2);
    font: 400 var(--fs-preview)/1.4 var(--font);
    cursor: pointer;
  }
  .sidebar-quiet-link:hover { color: var(--text); }
  .sidebar-error { padding: 10px; color: var(--danger); font: 400 var(--fs-preview)/1.4 var(--font); overflow-wrap: anywhere; }
  .sidebar-bottom { display: flex; align-items: center; gap: 10px; flex-shrink: 0; padding: 12px 14px calc(14px + env(safe-area-inset-bottom)); }
  .account-avatar {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 34px;
    height: 34px;
    padding: 0;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-avatar);
    background: var(--row-hover);
    color: var(--text-2);
    font: 500 var(--fs-time)/1 var(--font);
    cursor: pointer;
  }
  .account-avatar { overflow: hidden; }
  .account-avatar :global(.account-avatar-face) { display: grid; place-items: center; width: 100%; height: 100%; border-radius: inherit; }
  .account-avatar:hover { background: var(--row-selected); color: var(--text); }
  .account-avatar:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
  /* Reference: the pill fills the rest of the footer, its label centred. */

  /* On phones the sidebar is the home screen, so it takes the full width. */
  @media (max-width: 520px) {
    .sidebar.rail { width: 100%; max-width: 100%; }
  }
</style>
