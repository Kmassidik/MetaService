<script>
  /** Settings › Computer › Storage: the workspace and saved-files meters, and Manage files. */
  import SettingsGroup from './SettingsGroup.svelte'
  import SettingsRow from './SettingsRow.svelte'
  import { chat, loadStorage } from '../../lib/chatApp.svelte.js'
  import { NO_COMPUTER_NOTE, storageUsed, storageWarning } from './computerStatus.js'

  const NOT_CREATED = 'not_created'
  const ASLEEP_NOTE = 'Wake the computer to see live usage.'

  let { onOpen } = $props()

  const storage = $derived(chat.storage)
  const workspaceNote = $derived(storage?.computer?.state === NOT_CREATED ? NO_COMPUTER_NOTE : ASLEEP_NOTE)
  const systemLow = $derived(Boolean(storageWarning(storage?.computer?.system, 'System disk')))
  const warnings = $derived([
    storageWarning(storage?.computer?.workspace, 'Workspace'),
    storageWarning(storage?.results, 'Saved files'),
  ].filter(Boolean))
</script>

{#snippet refresh()}
  <button class="text-button" disabled={chat.storageLoading} onclick={loadStorage}>Refresh</button>
{/snippet}

{#snippet meter(label, usage, fallback)}
  <div class="meter">
    <div class="meter-line"><span>{label}</span><span class="meter-value">{usage ? storageUsed(usage) : fallback}</span></div>
    {#if usage}<progress class="meter-bar" aria-label={`${label} storage used`} value={usage.usedBytes} max={usage.limitBytes}></progress>{/if}
  </div>
{/snippet}

<SettingsGroup title="Storage" action={refresh}>
  {@render meter('Workspace', storage?.computer?.workspace, workspaceNote)}
  {@render meter('Saved files', storage?.results, '—')}
  <SettingsRow label="Manage files" onclick={() => onOpen('files')} />
</SettingsGroup>
{#each warnings as warning (warning)}<p class="environment-notice" role="status">{warning}</p>{/each}
{#if storage?.host?.writesAllowed === false}<p class="error-box" role="status">Server storage unavailable for new work.</p>{/if}
{#if systemLow}<p class="error-box" role="status">System disk is low — contact support.</p>{/if}
{#if chat.storageError}<p class="error-box" role="alert">{chat.storageError}</p>{/if}

<style>
  .meter { padding: 12px 14px; }
  .meter-line { display: flex; justify-content: space-between; gap: 12px; color: var(--text); font: 400 var(--fs-menu)/1.35 var(--font); }
  .meter-value { color: var(--text-2); text-align: right; }
  .meter-bar { margin-top: 9px; }
</style>
