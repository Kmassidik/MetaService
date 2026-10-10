<script>
  /**
   * Settings › Connected apps: the account's apps on the computer's browser (the shared P3 list),
   * with Connect / Check / Disconnect, plus a row into Connect apps to add more.
   */
  import { onMount } from 'svelte'
  import ConnectedAppsList from '../apps/ConnectedAppsList.svelte'
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import { chat, checkApp, connectApp, disconnectApp, openModal, refreshApps } from '../../lib/chatApp.svelte.js'
  import { MODALS } from '../../lib/constants.js'

  const NOTE = 'Apps sign in on your computer’s browser, and every bot can use them. Your passwords never go through chat.'

  let busyId = $state('')
  let error = $state('')

  /** One app action with its row locked; a failure shows under the list. */
  async function run(plugin, action) {
    error = ''
    busyId = plugin.id
    try {
      await action(plugin)
    } catch (failure) {
      error = failure.message || `Something went wrong with ${plugin.name}.`
    } finally {
      busyId = ''
    }
  }

  onMount(refreshApps)
</script>

<SettingsGroup title="On your computer" note={NOTE}>
  <div class="apps-list">
    <ConnectedAppsList
      apps={chat.computerApps} checkingId={chat.checkingAppId} {busyId}
      onConnect={plugin => run(plugin, connectApp)} onCheck={plugin => run(plugin, checkApp)} onDisconnect={plugin => run(plugin, disconnectApp)}
    />
  </div>
</SettingsGroup>
{#if error || chat.appsError}<p class="error-box" role="alert">{error || chat.appsError}</p>{/if}

<SettingsGroup>
  <SettingsRow label="Add apps" detail="Browse Google, X and more" onclick={() => openModal(MODALS.marketplace)} />
</SettingsGroup>

<style>
  .apps-list { padding: 4px 14px; }
  .apps-list :global(.app-rows-empty) { padding: 10px 0; }
  .apps-list :global(.app-row-button) { background: var(--surface); }
  /* A phone card is narrow: the actions drop under the app's name. */
  @media (max-width: 520px) {
    .apps-list :global(.app-row) { flex-wrap: wrap; }
    .apps-list :global(.app-row-actions) { width: 100%; padding-left: 32px; }
  }
</style>
