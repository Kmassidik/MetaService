<script>
  /**
   * The account's apps on the computer's browser, one row each, with Connect / Check / Disconnect.
   * Reusable: Connect apps shows it under "N connected"; Settings › Connected apps can mount it
   * with the same props (apps from `chat.computerApps`, handlers from lib/chat/apps.svelte.js).
   */
  import Icon from '../Icon.svelte'
  import { isAvailable, pluginById } from '../../lib/marketplace.js'
  import { AppState, appState, appStateLabel } from '../../lib/apps.js'

  let {
    apps = [],
    checkingId = '',
    busyId = '',
    emptyText = 'No apps connected yet. Connect one and every bot can use it.',
    onConnect,
    onCheck,
    onDisconnect,
  } = $props()

  // An app missing from this build’s catalog (an older page) has nothing to show, so it is skipped.
  // A Soon app still shows its last state and can be disconnected, but not connected or checked.
  const rows = $derived(apps.map(record => {
    const plugin = pluginById(record.appId)
    const state = appState(record, record.appId, checkingId)
    return { record, plugin, state, label: appStateLabel(state, record), soon: Boolean(plugin) && !isAvailable(plugin) }
  }).filter(row => row.plugin))

  const CHECK_ICON_SIZE = 12
  const locked = id => busyId === id || checkingId === id
</script>

{#if rows.length}
  <ul class="app-rows">
    {#each rows as row (row.record.appId)}
      <li class="app-row">
        <img class="app-row-logo" src={row.plugin.logo} alt="" width="22" height="22" />
        <div class="app-row-copy">
          <strong>{row.plugin.name}{#if row.soon}<span class="app-row-soon"><span aria-hidden="true">Soon</span><span class="sr-only">Coming soon</span></span>{/if}</strong>
          <small class:is-on={row.state === AppState.CONNECTED}>
            {#if row.state === AppState.CONNECTED}<Icon name="check" size={CHECK_ICON_SIZE} />{/if}{row.label}
          </small>
        </div>
        <div class="app-row-actions">
          {#if row.state === AppState.NEEDS_CHECK && !row.soon}
            <button type="button" class="app-row-button" disabled={locked(row.record.appId)} onclick={() => onCheck?.(row.plugin)}>Check</button>
            <button type="button" class="app-row-button" disabled={locked(row.record.appId)} onclick={() => onConnect?.(row.plugin)}>Connect</button>
          {/if}
          {#if row.state !== AppState.CHECKING}
            <button type="button" class="app-row-quiet" disabled={locked(row.record.appId)} onclick={() => onDisconnect?.(row.plugin)}>Disconnect</button>
          {/if}
        </div>
      </li>
    {/each}
  </ul>
{:else}
  <p class="app-rows-empty">{emptyText}</p>
{/if}

<style>
  .app-rows { list-style: none; margin: 0; padding: 0; display: grid; }
  .app-row { display: flex; align-items: center; gap: 10px; min-height: 48px; padding: 6px 0; border-top: 1px solid var(--hairline); }
  .app-row:first-child { border-top: 0; }
  .app-row-logo { width: 22px; height: 22px; padding: 2px; border-radius: var(--radius-item); background: var(--logo-backdrop); object-fit: contain; flex-shrink: 0; }
  .app-row-copy { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .app-row-copy strong { font: 500 14px/1.3 var(--font); color: var(--text); }
  .app-row-soon { margin-left: 6px; padding: 1px 7px; border: 1px solid var(--hairline); border-radius: var(--radius-pill); color: var(--text-2); font: 500 var(--fs-time)/1.3 var(--font); vertical-align: 1px; }
  .app-row-copy small { display: inline-flex; align-items: center; gap: 4px; color: var(--text-2); font: var(--fs-time)/1.3 var(--font); }
  .app-row-copy small.is-on { color: var(--ok-text); }
  .app-row-actions { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }
  .app-row-button, .app-row-quiet {
    min-height: 30px;
    padding: 0 12px;
    border-radius: var(--radius-pill);
    font: 500 var(--fs-time)/1 var(--font);
    white-space: nowrap;
    cursor: pointer;
  }
  .app-row-button { border: 1px solid var(--hairline); background: var(--page); color: var(--text); }
  .app-row-button:hover:not(:disabled) { border-color: var(--ink); background: var(--ink); color: var(--on-ink); }
  .app-row-quiet { border: 1px solid transparent; background: none; color: var(--text-2); }
  .app-row-quiet:hover:not(:disabled) { background: var(--row-hover); color: var(--text); }
  .app-row-button:disabled, .app-row-quiet:disabled { opacity: .45; cursor: default; }
  .app-rows-empty { margin: 0; color: var(--text-2); font: var(--fs-preview)/1.45 var(--font); }
</style>
