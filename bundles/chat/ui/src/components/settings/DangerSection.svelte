<script>
  /** Settings › Danger zone: delete the computer or the account, each behind a typed DELETE. */
  import { tick } from 'svelte'
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'
  import { chat, deleteAccount, manageEnvironment } from '../../lib/chatApp.svelte.js'
  import { SETTINGS } from '../../lib/settingsSections.js'

  const CONFIRM_WORD = 'DELETE'
  const FIELD_IDS = { computer: 'environment-confirmation', account: 'account-confirmation' }
  const TOGGLE_IDS = { computer: 'computer-deletion-toggle', account: 'account-deletion-toggle' }

  let { view, onSection, onOpen } = $props()

  const action = $derived(chat.environmentAction)
  const environment = $derived(chat.environment)
  const settling = $derived(view.environmentBusy || view.environmentTransitioning)

  function resetConfirmations(kind = '') {
    chat.confirmEnvironmentDeletion = kind === 'computer'
    chat.confirmAccountDeletion = kind === 'account'
    chat.environmentConfirmation = ''
    chat.accountConfirmation = ''
  }

  async function expand(kind) {
    resetConfirmations(kind)
    await tick()
    document.getElementById(FIELD_IDS[kind])?.focus()
  }

  async function cancel(kind) {
    resetConfirmations()
    await tick()
    document.getElementById(TOGGLE_IDS[kind])?.focus()
  }

  function deleteComputer(event) {
    event.preventDefault()
    manageEnvironment('delete')
  }
</script>

<p class="intro">These actions can’t be undone. To pause, put your computer to sleep instead.</p>
<div class="safe-actions">
  <button class="secondary-button" disabled={Boolean(action) || chat.deletingAccount} onclick={() => onSection(SETTINGS.computer)}>Computer controls</button>
  <button class="secondary-button" disabled={Boolean(action) || chat.deletingAccount} onclick={() => onOpen('files')}>Download saved files</button>
</div>

<section class="danger-card" aria-labelledby="computer-delete-title" aria-busy={action === 'delete'}>
  <div class="danger-heading"><Icon name="computer" size={ICON_SIZE.header} /><h3 id="computer-delete-title">Delete computer</h3></div>
  <p>Remove the private computer and everything stored inside it.</p>
  <dl><dt>Deleted</dt><dd>Computer workspace, browser profiles, all bots and teams, and their conversation histories.</dd><dt>Kept</dt><dd>Your account, usage record, connected-service settings, and separately saved uploads and Results.</dd></dl>
  {#if !environment}<p class="danger-status">No computer to delete.</p>
  {:else if environment.state === 'deleting'}<p class="environment-notice" role="status">Computer deletion is already in progress. Cleanup continues if you close Settings.</p>
  {:else}
    <button id={TOGGLE_IDS.computer} class="danger-button" type="button" aria-expanded={chat.confirmEnvironmentDeletion} aria-controls={chat.confirmEnvironmentDeletion ? 'computer-deletion-confirmation' : undefined} disabled={chat.loggingOut || chat.deletingAccount || chat.confirmEnvironmentDeletion} onclick={() => expand('computer')}>Delete computer…</button>
    {#if settling}<p class="danger-status">If something is still running, confirm below and we’ll stop it first.</p>{/if}
    {#if chat.confirmEnvironmentDeletion}
      <form id="computer-deletion-confirmation" class="danger-confirmation" onsubmit={deleteComputer}>
        <p id="computer-delete-warning"><strong>This deletes every bot and team—not just one chat.</strong> Any bots still working will be stopped first. Download workspace files you need. Files already in Results are kept.</p>
        <label class="form-label" for={FIELD_IDS.computer}>Type DELETE to confirm</label>
        <input id={FIELD_IDS.computer} class="form-input" bind:value={chat.environmentConfirmation} aria-describedby="computer-delete-warning" autocomplete="off" autocapitalize="off" spellcheck="false" required disabled={Boolean(action) || chat.deletingAccount} />
        <div class="confirm-actions"><button class="secondary-button" type="button" disabled={Boolean(action) || chat.deletingAccount} onclick={() => cancel('computer')}>Keep computer</button><button class="danger-button" type="submit" disabled={chat.environmentConfirmation !== CONFIRM_WORD || chat.loggingOut || chat.deletingAccount}>{action === 'delete' ? 'Deleting…' : 'Yes, delete computer'}</button></div>
      </form>
    {/if}
  {/if}
  {#if chat.environmentError}<p class="error-box" role="alert">{chat.environmentError}</p>{/if}
  {#if chat.environmentNotice}<p class="environment-notice" role="status">{chat.environmentNotice}</p>{/if}
</section>

<section class="danger-card" aria-labelledby="account-delete-title" aria-busy={chat.deletingAccount}>
  <div class="danger-heading"><Icon name="trash" size={ICON_SIZE.header} /><h3 id="account-delete-title">Delete account</h3></div>
  <p>Remove your account and all its data, including saved files outside the computer.</p>
  <dl><dt>Deleted</dt><dd>Account, computer, bots, teams, conversations, uploads, Results, connected services and stored credentials.</dd><dt>Access</dt><dd>You are signed out once deletion is accepted. Cleanup continues in the background. You can sign in with the same Google account again later, as a new person, and you will need an invite again.</dd></dl>
  <button id={TOGGLE_IDS.account} class="danger-button" type="button" aria-expanded={chat.confirmAccountDeletion} aria-controls={chat.confirmAccountDeletion ? 'account-deletion-confirmation' : undefined} disabled={chat.deletingAccount || chat.loggingOut || Boolean(action) || chat.confirmAccountDeletion} onclick={() => expand('account')}>Delete account…</button>
  {#if chat.confirmAccountDeletion}
    <form id="account-deletion-confirmation" class="danger-confirmation" onsubmit={deleteAccount}>
      <p id="account-deletion-warning"><strong>All account data will be permanently removed.</strong> Open bots will be stopped first. Download anything you need. This cannot be undone.</p>
      <label class="form-label" for={FIELD_IDS.account}>Type DELETE to confirm</label>
      <input id={FIELD_IDS.account} class="form-input" bind:value={chat.accountConfirmation} aria-describedby="account-deletion-warning" autocomplete="off" autocapitalize="off" spellcheck="false" required disabled={chat.deletingAccount || chat.loggingOut || Boolean(action)} />
      {#if chat.accountDeletionError}<p class="error-box" role="alert">{chat.accountDeletionError}</p>{/if}
      {#if chat.deletingAccount}<p role="status">Requesting permanent account deletion…</p>{/if}
      <div class="confirm-actions"><button class="secondary-button" type="button" disabled={chat.deletingAccount} onclick={() => cancel('account')}>Keep account</button><button class="danger-button" type="submit" disabled={chat.accountConfirmation !== CONFIRM_WORD || chat.deletingAccount || chat.loggingOut || Boolean(action)}>{chat.deletingAccount ? 'Deleting account…' : 'Yes, delete account'}</button></div>
    </form>
  {/if}
</section>

<style>
  .intro { color: var(--text-2); font: 400 var(--fs-preview)/1.5 var(--font); }
  .safe-actions { display: flex; flex-wrap: wrap; gap: 10px; margin: 14px 0 4px; }
  .safe-actions button { min-height: 34px; padding: 6px 14px; font-size: var(--fs-preview); }
  .danger-card { margin-top: 18px; padding: 16px; border-radius: var(--radius-card); background: var(--group); }
  .danger-heading { display: flex; gap: 10px; align-items: center; color: var(--danger); }
  h3 { font: 600 15px/1.4 var(--font); }
  .danger-card p { margin-top: 10px; font: 400 var(--fs-preview)/1.55 var(--font); }
  dl { display: grid; grid-template-columns: 64px minmax(0, 1fr); gap: 8px 12px; margin: 14px 0; font: var(--fs-preview)/1.5 var(--font); }
  dt { font-weight: 500; }
  dd { margin: 0; color: var(--text-2); }
  .danger-status { color: var(--text-2); }
  .danger-confirmation { margin-top: 16px; padding-top: 6px; border-top: 1px solid var(--group-line); }
  .confirm-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px; margin-top: 16px; }
  @media (max-width: 520px) { .danger-card { padding: 14px; } .confirm-actions button, .safe-actions button { flex: 1; } dl { grid-template-columns: 1fr; gap: 2px; } dd { margin-bottom: 8px; } }
</style>
