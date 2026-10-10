<script>
  /**
   * The one workspace <dialog>: picks the sheet for `chat.modal` and owns the shared sheet chrome.
   * Sheets read `chat` and `view` themselves, so App only mounts this with the view.
   */
  import Icon from '../Icon.svelte'
  import AgentFormSheet from './AgentFormSheet.svelte'
  import DeleteAgentSheet from './DeleteAgentSheet.svelte'
  import HelpSheet from './HelpSheet.svelte'
  import MarketplaceModal from './MarketplaceModal.svelte'
  import SettingsPanel from '../settings/SettingsPanel.svelte'
  import {
    chat, api, closeModal, resetAgentForm,
    connectApp, disconnectApp, checkApp, refreshApps,
  } from '../../lib/chatApp.svelte.js'
  import { MODALS } from '../../lib/constants.js'

  let { view } = $props()

  const FIXED_LABELS = {
    [MODALS.help]: 'Help',
    [MODALS.account]: 'Settings',
    [MODALS.marketplace]: 'Connect apps',
  }
  // Draw their own full-bleed header, so the shared close row is skipped.
  const FULL_BLEED = [MODALS.marketplace, MODALS.account]

  const modal = $derived(chat.modal)
  const closeLocked = $derived(chat.saving || chat.loggingOut || Boolean(chat.environmentAction) || chat.deletingAccount)

  // Screen readers need a name for every sheet; bot/group variants share one wording.
  function dialogLabel(kind, subject) {
    if (FIXED_LABELS[kind]) return FIXED_LABELS[kind]
    const noun = subject === 'team' ? 'group chat' : 'bot'
    if (kind === MODALS.delete) return `Confirm ${noun} deletion`
    return kind === MODALS.edit ? `Edit ${noun}` : `Create ${noun}`
  }

  function cancel(event) {
    event.preventDefault()
    closeModal()
  }

  // `close` also fires when a sheet swaps in place; only a real close resets the form.
  function closed() {
    if (chat.dialog?.open) return
    chat.modal = null
    resetAgentForm()
  }
</script>

<dialog
  bind:this={chat.dialog}
  class:full-bleed={FULL_BLEED.includes(modal)}
  class:settings={modal === MODALS.account}
  aria-label={dialogLabel(modal, chat.formKind)}
  oncancel={cancel}
  onclose={closed}
>
  {#if modal === MODALS.marketplace}
    <MarketplaceModal
      {api} connectors={chat.mentionConnectors} apps={chat.computerApps} checkingId={chat.checkingAppId} appsError={chat.appsError}
      onClose={closeModal} onConnectApp={connectApp} onDisconnectApp={disconnectApp}
      onCheckApp={checkApp} onRefreshApps={refreshApps} sessionKey={chat.session.csrf}
    />
  {:else if modal === MODALS.account && chat.session}
    <SettingsPanel {view} {closeLocked} />
  {:else if modal}
    <div class="modal-header">
      <button class="icon-button" aria-label="Close dialog" disabled={closeLocked} onclick={closeModal}><Icon name="close" size={19} /></button>
    </div>
    {#if modal === MODALS.create || modal === MODALS.edit}
      <AgentFormSheet {view} />
    {:else if modal === MODALS.help}
      <HelpSheet uploadLocked={view.uploadLocked} />
    {:else if modal === MODALS.delete}
      <DeleteAgentSheet />
    {/if}
  {/if}
</dialog>

<style>
  /* Every modal is a calm floating sheet; on phones it docks to the bottom edge. */
  dialog { width: min(520px, calc(100% - 48px)); max-height: calc(100dvh - 48px); padding: 0 24px 22px; overflow: auto; border: 0; border-radius: var(--radius-menu); background: var(--surface); color: var(--text); box-shadow: var(--shadow-float); }
  dialog::backdrop { background: var(--scrim); }
  /* The sheet itself takes focus when opened; its controls show the focus ring, not the whole sheet. */
  dialog:focus-visible { outline: none; }
  .full-bleed { width: min(680px, calc(100% - 48px)); max-height: min(860px, calc(100dvh - 48px)); padding: 0; overflow: hidden; }
  .settings { width: min(760px, calc(100% - 48px)); height: min(560px, calc(100dvh - 48px)); }
  .modal-header { position: sticky; top: 0; z-index: 1; display: flex; align-items: center; gap: 12px; min-height: 56px; margin: 0 -24px 4px; padding: 10px 14px 0 24px; background: var(--surface); }
  .modal-header .icon-button { margin-left: auto; }
  /* Shared by every sheet rendered inside this dialog. */
  dialog :global(h2) { font: 600 20px/1.3 var(--font); color: var(--text); overflow-wrap: anywhere; }
  dialog :global(.modal-description) { margin: 10px 0 20px; color: var(--text-2); font: 14px/1.6 var(--font); }
  dialog :global(.modal-actions) { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px; margin: 28px 0 0; }
  dialog :global(.modal-actions :is(.primary-button, .secondary-button, .danger-button)) { padding: 9px 18px; font-size: 14px; }
  dialog :global(.modal-actions > :last-child) { margin-left: auto; }
  @media (max-width: 520px) {
    dialog, .full-bleed { width: 100%; max-width: 100%; max-height: 92dvh; margin: auto 0 0; border-radius: var(--radius-menu) var(--radius-menu) 0 0; }
    dialog { padding: 0 18px max(18px, env(safe-area-inset-bottom)); }
    .full-bleed { padding: 0; }
    /* Settings is a full screen on a phone, like the iOS app. */
    .settings { height: 100dvh; max-height: 100dvh; margin: 0; border-radius: 0; }
    .modal-header { margin: 0 -18px 4px; padding: 8px 10px 0 18px; }
    dialog :global(.modal-actions) { margin: 22px 0 0; }
    dialog :global(.modal-actions button) { flex: 1; }
  }
</style>
