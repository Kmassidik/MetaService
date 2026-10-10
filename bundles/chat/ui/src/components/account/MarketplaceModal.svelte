<script>
  import { onMount } from 'svelte'
  import Icon from '../Icon.svelte'
  import './plugin-sheet.css'
  import ConnectorPanel from './ConnectorPanel.svelte'
  import ConnectedAppsList from '../apps/ConnectedAppsList.svelte'
  import { catalogPlugins, isAvailable, pluginById, pluginCategories } from '../../lib/marketplace.js'
  import { AppState, appRecord, appState, appStateLabel, connectedAppList, offeredApps } from '../../lib/apps.js'

  let {
    api,
    connectors = [],
    apps = [],
    checkingId = '',
    appsError = '',
    sessionKey,
    onClose,
    onConnectApp,
    onDisconnectApp,
    onCheckApp,
    onRefreshApps,
  } = $props()

  let query = $state('')
  let notice = $state('')
  let error = $state('')
  let busyId = $state('')
  let showInstalled = $state(false)
  let showAdvanced = $state(false)
  let infoId = $state('')
  let categoryFilter = $state('all')

  const liveConnectors = $derived((connectors || []).filter(item => !item.revoked))
  const installedCount = $derived(connectedAppList(offeredApps(apps, pluginById)).length + liveConnectors.length)
  const shownError = $derived(error || appsError)

  function cardState(plugin) {
    return appState(appRecord(apps, plugin.id), plugin.id, checkingId)
  }

  function matches(plugin) {
    if (categoryFilter !== 'all' && plugin.category !== categoryFilter) return false
    const q = query.trim().toLowerCase()
    if (!q) return true
    return `${plugin.name} ${plugin.blurb} ${plugin.category}`.toLowerCase().includes(q)
  }

  const visible = $derived(catalogPlugins.filter(matches))

  const sections = $derived.by(() => {
    const q = query.trim()
    const cats = categoryFilter === 'all'
      ? pluginCategories
      : pluginCategories.filter(c => c.id === categoryFilter)
    return cats
      .map(cat => ({
        ...cat,
        items: visible.filter(p => p.category === cat.id),
      }))
      .filter(sec => sec.items.length > 0 || (!q && categoryFilter !== 'all'))
  })

  function toggleInfo(id) {
    infoId = infoId === id ? '' : id
  }

  /** Runs one app action with the card locked; a failure shows in the sheet's error box. */
  async function run(plugin, action, done = '') {
    error = ''
    notice = ''
    busyId = plugin.id
    try {
      await action()
      notice = done
    } catch (failure) {
      error = failure.message || `Something went wrong with ${plugin.name}.`
    } finally {
      busyId = ''
    }
  }

  const connect = plugin => run(plugin, () => onConnectApp?.(plugin))
  const disconnect = plugin => run(plugin, () => onDisconnectApp?.(plugin), `${plugin.name} disconnected. Sign out on your computer to remove the login too.`)

  async function check(plugin) {
    await run(plugin, () => onCheckApp?.(plugin))
    if (error) return
    notice = cardState(plugin) === AppState.CONNECTED ? `${plugin.name} is connected.` : `${plugin.name} isn’t signed in on your computer yet.`
  }

  async function refresh() {
    try {
      await onRefreshApps?.()
    } catch (failure) {
      error = failure.message || 'Could not check your apps.'
    }
  }

  onMount(refresh)
</script>

<div class="plugins">
  <header class="plugins-top">
    <div class="plugins-title-row">
      <div>
        <h2>Connect apps</h2>
        <p>Sign in once on your computer’s browser and every bot can use it. Connected only after Ruvio checks the login. Your password never enters chat. Apps marked Soon open up once Ruvio can check their sign-in.</p>
      </div>
      <button type="button" class="plugins-installed" onclick={() => showInstalled = !showInstalled} aria-expanded={showInstalled}>
        {installedCount} connected
      </button>
      <button type="button" class="icon-button" aria-label="Close connect apps" onclick={onClose}><Icon name="close" size={18} /></button>
    </div>
    <label class="plugins-search">
      <Icon name="search" size={16} />
      <input type="search" placeholder="Search apps" bind:value={query} aria-label="Search apps" />
    </label>
    <div class="plugins-cats" role="tablist" aria-label="App categories">
      <button type="button" role="tab" aria-selected={categoryFilter === 'all'} class:is-on={categoryFilter === 'all'} onclick={() => categoryFilter = 'all'}>All</button>
      {#each pluginCategories as cat (cat.id)}
        <button type="button" role="tab" aria-selected={categoryFilter === cat.id} class:is-on={categoryFilter === cat.id} onclick={() => categoryFilter = cat.id}>{cat.label}</button>
      {/each}
    </div>
    {#if showInstalled}
      <div class="plugins-installed-panel">
        <ConnectedAppsList {apps} {checkingId} {busyId} onConnect={connect} onCheck={check} onDisconnect={disconnect} />
        {#if liveConnectors.length}
          <ul class="plugins-connectors">
            {#each liveConnectors as item (item.id)}
              <li><strong>{item.name}</strong><small>Custom connector</small></li>
            {/each}
          </ul>
        {/if}
      </div>
    {/if}
  </header>

  {#if shownError}<div class="error-box" role="alert">{shownError}</div>{/if}
  {#if notice}<p class="plugins-notice" role="status">{notice}</p>{/if}

  <div class="plugins-body">
    {#each sections as section (section.id)}
      <section class="plugins-section">
        <h3>{section.label}</h3>
        <ul class="plugins-grid">
          {#each section.items as plugin (plugin.id)}
            {@const soon = !isAvailable(plugin)}
            <li class="plugin-card" class:is-soon={soon} aria-disabled={soon ? 'true' : undefined}>
              <div class="plugin-head">
                <img class="plugin-logo" src={plugin.logo} alt="" width="24" height="24" />
                {#if !soon}
                  <button type="button" class="plugin-info" aria-label={`How to connect ${plugin.name}`} aria-expanded={infoId === plugin.id} onclick={() => toggleInfo(plugin.id)}><Icon name="info" size={14} /></button>
                {/if}
              </div>
              <div class="plugin-copy">
                <strong>{plugin.name}</strong>
                <p>{plugin.blurb}</p>
              </div>
              {#if infoId === plugin.id}
                <p class="plugin-how" role="note">{plugin.how}</p>
              {/if}
              <div class="plugin-actions">
                {#if soon}
                  <span class="plugin-soon"><span aria-hidden="true">Soon</span><span class="sr-only">Coming soon</span></span>
                {:else if cardState(plugin) === AppState.CONNECTED}
                  <span class="plugin-added"><Icon name="check" size={12} /> Connected</span>
                  <button type="button" class="text-button" disabled={busyId === plugin.id} onclick={() => disconnect(plugin)}>Disconnect</button>
                {:else if cardState(plugin) === AppState.CHECKING}
                  <span class="plugin-checking" role="status">Checking…</span>
                {:else if cardState(plugin) === AppState.NEEDS_CHECK}
                  <button type="button" class="plugin-add" disabled={busyId === plugin.id} onclick={() => check(plugin)}>Check login</button>
                  <button type="button" class="text-button" disabled={busyId === plugin.id} onclick={() => connect(plugin)}>Connect</button>
                  <small class="plugin-state">{appStateLabel(AppState.NEEDS_CHECK, appRecord(apps, plugin.id))}</small>
                {:else}
                  <button type="button" class="plugin-add" disabled={busyId === plugin.id} onclick={() => connect(plugin)}>{busyId === plugin.id ? '…' : 'Connect'}</button>
                {/if}
              </div>
            </li>
          {/each}
        </ul>
      </section>
    {:else}
      <p class="plugins-empty">No apps match “{query.trim() || categoryFilter}”.</p>
    {/each}
  </div>

  <footer class="plugins-foot">
    <button type="button" class="text-button" aria-expanded={showAdvanced} onclick={() => showAdvanced = !showAdvanced}>{showAdvanced ? 'Hide custom connectors' : 'Custom connectors (advanced)…'}</button>
    {#if showAdvanced}<ConnectorPanel {api} {sessionKey} />{/if}
  </footer>
</div>
