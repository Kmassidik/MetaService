<script>
  /** The stack above the computer screen: connect banner, control and error notes, address bar, teach sheet. */
  import DeskConnectBanner from './DeskConnectBanner.svelte'
  import DeskNotice from './DeskNotice.svelte'
  import DeskAddressBar from './DeskAddressBar.svelte'
  import DeskTeachSheet from './DeskTeachSheet.svelte'

  let {
    botName = '',
    connectingApp = null,
    connectProbeError = '',
    takingOver = false,
    blocked = false,
    serverNote = false,
    message = '',
    error = '',
    showAddress = false,
    showTeach = false,
    locked = false,
    teachLocked = false,
    url = $bindable(''),
    teachName = $bindable(''),
    teachDescription = $bindable(''),
    onFinishConnect,
    onCancelConnect,
    onAction,
    onTeach,
    onCloseTeach,
  } = $props()

  // One place decides what is visible, so the divider below the stack can never disagree with it.
  const shown = $derived({
    connect: Boolean(connectingApp),
    control: takingOver && !connectingApp,
    blocked,
    server: serverNote,
    error: Boolean(error),
    address: showAddress,
    teach: showTeach,
  })
  const hasNotices = $derived(Object.values(shown).some(Boolean))
</script>

<div class="desk-notices" class:has-notices={hasNotices}>
  {#if shown.connect}<DeskConnectBanner appName={connectingApp.name} disabled={locked} probeError={connectProbeError} onFinish={onFinishConnect} onCancel={onCancelConnect} />{/if}
  {#if shown.control}<DeskNotice tone="control">You’re in control. {botName} waits until you hand back.</DeskNotice>{/if}
  {#if shown.blocked}<DeskNotice tone="error">{message}</DeskNotice>{/if}
  {#if shown.server}<DeskNotice>{message}</DeskNotice>{/if}
  {#if shown.error}<DeskNotice tone="error">{error}<button class="text-button" disabled={locked} onclick={() => onAction?.('status')}>Refresh status</button></DeskNotice>{/if}
  {#if shown.address}<DeskAddressBar bind:url disabled={locked} onOpen={() => onAction?.('open')} />{/if}
  {#if shown.teach}<DeskTeachSheet bind:name={teachName} bind:description={teachDescription} locked={teachLocked} {onTeach} onClose={onCloseTeach} />{/if}
</div>

<style>
  .desk-notices { flex-shrink: 0; }
  .desk-notices.has-notices { padding-bottom: 8px; border-bottom: 1px solid var(--hairline); }
</style>
