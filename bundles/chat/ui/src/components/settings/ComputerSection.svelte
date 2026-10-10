<script>
  /** Settings › Computer: status, wake or sleep, open it, and storage. */
  import Icon from '../Icon.svelte'
  import { ICON_SIZE } from '../../lib/constants.js'
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import StorageGroup from './StorageGroup.svelte'
  import { chat, loadEnvironment, manageEnvironment } from '../../lib/chatApp.svelte.js'
  import { computerStatusLabel, computerStatusNote } from './computerStatus.js'

  const WORKING_STATES = ['running', 'provisioning']

  let { view, onOpen } = $props()

  const environment = $derived(chat.environment)
  const action = $derived(chat.environmentAction)
  const busy = $derived(view.environmentBusy || chat.loggingOut)
  const settling = $derived(Boolean(action) || view.environmentTransitioning)
  const working = $derived(Boolean(chat.pending || chat.agents.some(agent => WORKING_STATES.includes(agent.status))))
</script>

{#snippet refresh()}
  <button class="icon-button" aria-label="Refresh computer status" disabled={chat.environmentLoading || Boolean(action)} onclick={loadEnvironment}><Icon name="refresh" size={ICON_SIZE.inline} /></button>
{/snippet}

<SettingsGroup title="Your computer" action={refresh}>
  <SettingsRow label="Status" detail={computerStatusNote(environment)}>
    <span class="status" aria-busy={Boolean(action)}>
      {#if chat.environmentLoading}<span class="tiny-spinner" aria-label="Refreshing"></span>{/if}
      <span class="dot" class:awake={environment?.state === 'ready'}></span>{computerStatusLabel(environment, action)}
    </span>
  </SettingsRow>
  {#if environment?.state === 'suspended'}
    <SettingsRow label="Wake computer" disabled={busy || view.environmentTransitioning} onclick={() => manageEnvironment('wake')} />
  {:else if environment?.state === 'ready'}
    <SettingsRow label="Put to sleep" disabled={busy || view.hasTakeover} onclick={() => manageEnvironment('suspend')} />
  {/if}
  {#if environment}
    <SettingsRow label="Open computer" disabled={settling} onclick={() => onOpen('computer')} />
  {/if}
</SettingsGroup>
{#if view.hasTakeover}<p class="environment-notice" role="status">Open Computer and tap Give back before sleeping the machine.</p>{/if}
{#if working}<p class="form-help">Wait for active tasks to finish before sleeping.</p>{/if}
{#if chat.uploads.length > 0}<p class="form-help">Finish uploads first.</p>{/if}
{#if environment?.lastError}<p class="error-box" role="alert">{environment.lastError}</p>{/if}
{#if chat.environmentNotice}<p class="environment-notice" role="status">{chat.environmentNotice}</p>{/if}
{#if chat.environmentError}<p class="error-box" role="alert">{chat.environmentError}</p>{/if}
{#if chat.environmentRefreshError}<p class="error-box" role="alert">Could not refresh. Retrying…</p>{/if}

<StorageGroup {onOpen} />

<style>
  .status { display: inline-flex; align-items: center; gap: 8px; color: var(--text-2); white-space: nowrap; }
  .dot { width: 8px; height: 8px; border-radius: var(--radius-avatar); background: var(--text-3); }
  .dot.awake { background: var(--ok); }
</style>
