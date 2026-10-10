<script>
  /**
   * The computer opened big (Open on the side panel's preview, Connect apps, a takeover card):
   * it covers the chat area on desktop and the whole screen on phone, with Take control / Give back.
   * Full screen puts this whole view (top bar + desktop) on the monitor, like Remmina or AnyDesk.
   * Esc there is the browser's: it leaves full screen and never reaches the remote desktop.
   */
  import DeskToolbar from './DeskToolbar.svelte'
  import DeskNotices from './DeskNotices.svelte'
  import DeskStage from './DeskStage.svelte'
  import DeskKeyboard from './DeskKeyboard.svelte'
  import DeskFullScreenExit from './DeskFullScreenExit.svelte'
  import { FullScreenMode, createFullScreen } from './fullScreen.js'
  import { DeskPhase, canTakeOver, deskPhase, homeHint, isBlocked, isStreamMode, isStreamReconnecting, liveLabel, streamSource } from './deskStatus.js'
  import { COMPUTER_VIEW_ID } from '../../lib/chat/computer.svelte.js'

  const BROWSER_HOME = 'https://www.google.com'
  // All bots share one computer, so the view is the owner's, not a bot's.
  const TITLE = 'Your computer'
  const SETUP_TEXT = 'Setting up your computer… about 15 seconds'

  let {
    open = false,
    active = null,
    pending = null,
    takingOver = false,
    connectingApp = null,
    connectProbeError = '',
    onFinishConnect,
    onCancelConnect,
    url = $bindable('https://example.com'),
    text = $bindable(''),
    teachOpen = $bindable(false),
    teachName = $bindable(''),
    teachDescription = $bindable(''),
    busy = false,
    error = '',
    updated = '',
    image = '',
    message = '',
    pageUrl = '',
    desktop = null,
    settingUp = false,
    onClose,
    onOpenFiles,
    onAction,
    onClickScreenshot,
    onTeach,
    onFocusChat,
  } = $props()

  let addressOpen = $state(false)
  let computerBody = $state(null)
  let panel = $state(null)
  let fullScreenView = $state({ mode: FullScreenMode.OFF, controlsVisible: false })
  const fullScreen = createFullScreen({ doc: document, onChange: (change) => { fullScreenView = change } })

  const locked = $derived(Boolean(busy) || Boolean(pending))
  const phase = $derived(deskPhase({ desktop, image, message, busy }))
  const streamMode = $derived(isStreamMode(desktop))
  const reconnecting = $derived(isStreamReconnecting(desktop))
  const blocked = $derived(isBlocked(message))
  const canTeach = $derived(Boolean(active) && active.kind !== 'team' && !connectingApp)
  const hasComputer = $derived(Boolean(active) || Boolean(connectingApp))
  const showAddress = $derived(addressOpen || phase === DeskPhase.SNAPSHOT)
  const showServerNote = $derived(Boolean(message) && phase === DeskPhase.SNAPSHOT && !blocked)
  const menuItems = $derived(computerMenu())
  const isFullScreen = $derived(fullScreenView.mode !== FullScreenMode.OFF)

  // Closing the view (or leaving Chat) never leaves the browser in full screen.
  $effect(() => { if (!open) fullScreen.exit() })
  $effect(() => () => fullScreen.dispose())

  function startingText() {
    if (settingUp) return SETUP_TEXT
    if (connectingApp) return `Opening ${connectingApp.name}…`
    return 'Starting your computer…'
  }

  function toolbarStatus() {
    if (reconnecting) return 'Reconnecting'
    return liveLabel(phase, updated)
  }

  function computerMenu() {
    const items = [
      { id: 'address', label: addressOpen ? 'Hide web address' : 'Open a web address', icon: 'search', disabled: false, onSelect: () => { addressOpen = !addressOpen } },
      { id: 'files', label: 'Files', icon: 'folder', disabled: false, onSelect: openFiles },
      { id: 'refresh', label: 'Refresh status', icon: 'refresh', disabled: locked, onSelect: () => onAction?.('status') },
    ]
    if (!canTeach) return items
    return [{ id: 'teach', label: 'Teach a task', icon: 'spark', disabled: false, onSelect: () => { teachOpen = true } }, ...items]
  }

  function closeOnEscape(event) {
    if (event.key !== 'Escape' || event.defaultPrevented) return
    event.preventDefault()
    if (isFullScreen) return fullScreen.exit()
    onClose?.()
  }

  // Esc typed into the desktop: out of full screen first, back to the chat the next time.
  function escapeFromDesktop() {
    if (isFullScreen) return fullScreen.exit()
    returnFocusToChat()
  }

  // Files opens over Chat, outside this view, so it can't show while the view is full screen.
  function openFiles() {
    fullScreen.exit()
    onOpenFiles?.()
  }

  // App wires onFocusChat to the composer; without it, keep focus inside the view rather than lose it.
  function returnFocusToChat() {
    if (onFocusChat) return onFocusChat()
    computerBody?.focus()
  }

  function openBrowserHome() {
    url = BROWSER_HOME
    onAction?.('open')
  }
</script>

<svelte:document onfullscreenchange={fullScreen.syncWithDocument} />

{#if open}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <aside
    id="computer-panel"
    class="desk-panel"
    class:is-full-viewport={fullScreenView.mode === FullScreenMode.FALLBACK}
    aria-label={TITLE}
    bind:this={panel}
    onkeydown={closeOnEscape}
    onpointermove={fullScreen.revealControls}
    onpointerdown={fullScreen.revealControls}
  >
    <DeskToolbar
      title={TITLE}
      liveText={toolbarStatus()}
      live={phase === DeskPhase.STREAM && !reconnecting}
      busy={Boolean(busy)}
      showTakeover={Boolean(active) && !connectingApp}
      {takingOver}
      takeoverDisabled={locked || !canTakeOver(phase)}
      {menuItems}
      showFullScreen={hasComputer || isFullScreen}
      fullScreen={isFullScreen}
      onToggleFullScreen={() => fullScreen.toggle(panel)}
      onTakeOver={() => onAction?.('takeover')}
      onHandBack={() => onAction?.('release')}
      {onClose}
    />

    {#if !hasComputer}
      <div id={COMPUTER_VIEW_ID} class="desk-body" tabindex="-1">
        <DeskStage phase={DeskPhase.HOME} hint="Select a bot to start its computer." locked />
      </div>
    {:else}
      <div id={COMPUTER_VIEW_ID} class="desk-body" tabindex="-1" aria-label={TITLE} bind:this={computerBody}>
        <DeskNotices
          botName={active?.name || ''} {connectingApp} {connectProbeError} {takingOver} {blocked} serverNote={showServerNote}
          {message} {error} {showAddress} showTeach={teachOpen && canTeach} {locked} teachLocked={Boolean(pending)}
          bind:url bind:teachName bind:teachDescription
          {onFinishConnect} {onCancelConnect} {onAction} {onTeach} onCloseTeach={() => { teachOpen = false }}
        />
        <DeskStage
          {phase}
          startingText={startingText()}
          streamSrc={streamSource(desktop)}
          {reconnecting}
          {image}
          {takingOver}
          {locked}
          hint={homeHint({ message, image })}
          {onClickScreenshot}
          onOpenBrowser={openBrowserHome}
          onOpenFiles={openFiles}
          onEscape={escapeFromDesktop}
          fullScreen={isFullScreen}
          onActivity={fullScreen.revealControls}
        />
        {#if isFullScreen}<DeskFullScreenExit visible={fullScreenView.controlsVisible} onExit={fullScreen.exit} />{/if}
        {#if pageUrl && phase === DeskPhase.SNAPSHOT}<p class="desk-caption">{pageUrl}</p>{/if}
        {#if takingOver && !streamMode}<DeskKeyboard bind:text {busy} {locked} onAction={(action, fields) => onAction?.(action, fields)} />{/if}
      </div>
    {/if}
  </aside>
{/if}

<style>
  /* An absolute grid child uses its grid area as the containing block: this covers the chat area only.
     Both lines are explicit; an absolute item's `auto` end line is the grid's edge, not the next line. */
  .desk-panel {
    position: absolute;
    inset: 0;
    z-index: 20;
    grid-column: 2 / 3;
    grid-row: 1 / 2;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: var(--page);
  }
  .desk-body { position: relative; flex: 1; min-height: 0; display: flex; flex-direction: column; outline: none; }
  /* Full screen without the Fullscreen API (iOS Safari): cover the whole viewport, above the chat
     and the side panel but below menus and file viewers. */
  .desk-panel.is-full-viewport { position: fixed; inset: 0; z-index: 60; }
  .desk-caption {
    padding: 6px 14px;
    border-top: 1px solid var(--hairline);
    color: var(--text-2);
    font: 400 var(--fs-time)/1.4 var(--font);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  @media (max-width: 820px) {
    .desk-panel { position: fixed; z-index: 35; }
    .desk-panel.is-full-viewport { z-index: 60; }
  }
</style>
