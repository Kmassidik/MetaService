<script>
  import { onMount, onDestroy } from 'svelte'
  import Icon from '../Icon.svelte'
  let { api, sessionKey, disabled = false } = $props()
  let connectors = $state([])
  let approvals = $state([])
  let tools = $state({})
  let selectedTools = $state({})
  let args = $state({})
  let checked = $state({})
  let results = $state({})
  let attempted = $state({})
  let name = $state('')
  let endpoint = $state('')
  let bearerToken = $state('')
  let tokenVisible = $state(false)
  let error = $state('')
  let notice = $state('')
  let busy = $state('')
  let loading = $state(false)
  let registrationBlocked = $state(false)
  let revokeId = $state('')
  let now = $state(Date.now())
  let showAdvanced = $state(false)
  let alive = true
  let revision = 0
  let refreshTimer
  let clockTimer
  const requests = new Set()
  const bytes = value => new TextEncoder().encode(value).length
  const blocked = $derived(disabled || Boolean(busy) || loading)
  const activeConnectors = $derived(connectors.filter(item => !item.revoked))
  const pendingApprovals = $derived(approvals.filter(item => ['pending', 'approved', 'executing', 'uncertain'].includes(item.state)))

  async function request(path, options = {}) {
    const key = sessionKey
    const controller = new AbortController()
    requests.add(controller)
    try {
      const data = await api(path, { ...options, signal: controller.signal })
      if (!alive || key !== sessionKey) throw new DOMException('Session changed', 'AbortError')
      return data
    } finally { requests.delete(controller) }
  }

  async function refresh(manual = false) {
    if (busy || loading || disabled) return
    const version = ++revision
    loading = true
    if (manual) { error = ''; registrationBlocked = false }
    try {
      const [connectorData, approvalData] = await Promise.all([request('/api/connectors'), request('/api/connector-approvals')])
      if (!alive || version !== revision) return
      connectors = connectorData.connectors
      approvals = approvalData.approvals
    } catch (failure) {
      if (alive && version === revision && failure.name !== 'AbortError') error = failure.message || 'Could not refresh apps.'
    } finally { if (alive && version === revision) loading = false }
  }

  async function register(event) {
    event.preventDefault()
    if (blocked || registrationBlocked || !name.trim() || !endpoint.trim()) return
    error = ''; notice = ''
    let body
    try {
      if (bytes(name.trim()) > 120 || bytes(endpoint.trim()) > 2048 || bytes(bearerToken) > 8192) throw new Error('Name, endpoint or token is too large.')
      const url = new URL(endpoint.trim())
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.port && url.port !== '443')) throw new Error('Use an HTTPS URL on port 443 with no credentials or query.')
      body = JSON.stringify({ name: name.trim(), endpoint: url.href, ...(bearerToken ? { bearerToken } : {}) })
      if (bytes(body) > 30000) throw new Error('Settings are too large.')
    } catch (failure) { error = failure.message; return }
    busy = 'register'
    bearerToken = ''
    tokenVisible = false
    try {
      const data = await request('/api/connectors', { method: 'POST', body })
      connectors = [...connectors.filter(item => item.id !== data.connector.id), data.connector]
      name = ''; endpoint = ''
      notice = 'Connected. You can discover tools below if needed.'
      showAdvanced = true
    } catch (failure) {
      if (alive && failure.name !== 'AbortError') {
        error = failure.message || 'Could not connect.'
        registrationBlocked = /allowlist|not configured|disabled by|connectors? (?:are |is )?disabled/i.test(error)
      }
    } finally { if (alive) busy = '' }
  }

  async function discover(connector) {
    if (blocked || connector.revoked) return
    busy = `discover:${connector.id}`; error = ''; notice = ''
    try {
      const data = await request(`/api/connectors/${encodeURIComponent(connector.id)}/discover`, { method: 'POST' })
      tools = { ...tools, [connector.id]: data.tools }
      selectedTools = { ...selectedTools, [connector.id]: '' }
      notice = `Found ${(data.tools || []).length} tools for ${connector.name}.`
    } catch (failure) { if (alive && failure.name !== 'AbortError') error = failure.message || 'Could not discover tools.' }
    finally { if (alive) busy = '' }
  }

  async function revoke(connector) {
    if (blocked) return
    busy = `revoke:${connector.id}`; error = ''; notice = ''
    try {
      await request(`/api/connectors/${encodeURIComponent(connector.id)}`, { method: 'DELETE' })
      connectors = connectors.map(item => item.id === connector.id ? { ...item, revoked: true } : item)
      tools = { ...tools, [connector.id]: [] }
      checked = {}; revokeId = ''
      notice = `${connector.name} disconnected.`
    } catch (failure) { if (alive && failure.name !== 'AbortError') error = failure.message || 'Could not disconnect.' }
    finally { if (alive) { busy = ''; await refresh() } }
  }

  async function prepare(connector) {
    if (blocked || connector.revoked) return
    error = ''; notice = ''
    const tool = selectedTools[connector.id]
    const argsJSON = args[connector.id] || '{}'
    try {
      if (bytes(argsJSON) > 24000) throw new Error('Arguments are too large.')
      const value = JSON.parse(argsJSON)
      if (!value || Array.isArray(value) || typeof value !== 'object') throw new Error('Arguments must be a JSON object.')
      if (!tool || !(tools[connector.id] || []).some(item => item.name === tool)) throw new Error('Pick a tool first.')
      if (bytes(JSON.stringify({ tool, argsJSON })) > 30000) throw new Error('Arguments are too large.')
    } catch (failure) { error = failure.message; return }
    busy = `prepare:${connector.id}`
    try {
      const data = await request(`/api/connectors/${encodeURIComponent(connector.id)}/approvals`, { method: 'POST', body: JSON.stringify({ tool, argsJSON }) })
      approvals = [data.approval, ...approvals.filter(item => item.id !== data.approval.id)]
      notice = 'Ready for review — approve before anything runs.'
    } catch (failure) { if (alive && failure.name !== 'AbortError') error = failure.message || 'Could not prepare approval.' }
    finally { if (alive) busy = '' }
  }

  function expired(approval) { return !Number.isFinite(Date.parse(approval.expiresAt)) || Date.parse(approval.expiresAt) <= now }
  function signature(approval) { return `${approval.actionHash}:${approval.argsJSON}:${approval.tool}:${approval.connectorId}` }
  function connectorFor(approval) { return connectors.find(item => item.id === approval.connectorId) }
  function executable(approval) { return !blocked && !attempted[approval.id] && approval.state === 'approved' && !expired(approval) && connectorFor(approval) && !connectorFor(approval).revoked && checked[approval.id] === signature(approval) }

  async function decide(approval, approve) {
    if (blocked || approval.state !== 'pending' || expired(approval) || (approve && checked[approval.id] !== signature(approval))) return
    busy = `decision:${approval.id}`; error = ''; notice = ''
    try {
      await request(`/api/connector-approvals/${encodeURIComponent(approval.id)}/decision`, { method: 'POST', body: JSON.stringify({ approve }) })
      notice = approve ? 'Approved. Execute when you’re ready.' : 'Denied.'
    } catch (failure) { if (alive && failure.name !== 'AbortError') error = failure.message || 'Decision failed.' }
    finally { if (alive) { busy = ''; await refresh() } }
  }

  async function execute(approval) {
    if (!executable(approval)) return
    busy = `execute:${approval.id}`; error = ''; notice = ''
    attempted = { ...attempted, [approval.id]: true }
    try {
      const data = await request(`/api/connector-approvals/${encodeURIComponent(approval.id)}/execute`, { method: 'POST' })
      results = { ...results, [approval.id]: JSON.stringify(data.result, null, 2) }
      checked = { ...checked, [approval.id]: '' }
      notice = 'Done. Check the result if you need it.'
    } catch (failure) {
      if (alive && failure.name !== 'AbortError') error = failure.message || 'Execution response unavailable. Verify the destination before retrying.'
    } finally { if (alive) { busy = ''; await refresh() } }
  }

  onMount(() => {
    refresh()
    refreshTimer = setInterval(() => refresh(), 5000)
    clockTimer = setInterval(() => now = Date.now(), 1000)
  })
  onDestroy(() => {
    alive = false; bearerToken = ''
    clearInterval(refreshTimer); clearInterval(clockTimer)
    for (const controller of requests) controller.abort()
  })
</script>

<section class="apps-settings" aria-labelledby="apps-title">
  <div class="apps-heading">
    <div>
      <h3 id="apps-title">Custom connectors</h3>
      <p>Your own HTTPS connectors, for services not listed above. You’ll still approve each sensitive action.</p>
    </div>
    <button class="icon-button" aria-label="Refresh custom connectors" disabled={blocked || loading} onclick={() => refresh(true)}><Icon name="refresh" size={15} /></button>
  </div>

  {#if error}<div class="error-box" role="alert">{error}</div>{/if}
  {#if notice}<p class="apps-notice" role="status">{notice}</p>{/if}

  {#if loading && !connectors.length}
    <p class="apps-empty" role="status">Loading…</p>
  {:else if !activeConnectors.length}
    <div class="apps-empty-card">
      <Icon name="apps" size={22} />
      <p>No custom connectors yet.</p>
      <button type="button" class="secondary-button" disabled={blocked || registrationBlocked} onclick={() => showAdvanced = true}>Add a connector</button>
    </div>
  {:else}
    <ul class="apps-list">
      {#each activeConnectors as connector (connector.id)}
        <li class="apps-row">
          <span class="apps-icon" aria-hidden="true"><Icon name="apps" size={16} /></span>
          <span class="apps-copy">
            <strong>{connector.name}</strong>
            <small>Connected</small>
          </span>
          <button type="button" class="text-button" disabled={blocked} onclick={() => revokeId = connector.id}>Disconnect</button>
        </li>
        {#if revokeId === connector.id}
          <li class="apps-confirm">
            <p>Disconnect {connector.name}?</p>
            <div class="file-actions">
              <button class="danger-button" disabled={blocked} onclick={() => revoke(connector)}>Disconnect</button>
              <button class="secondary-button" disabled={blocked} onclick={() => revokeId = ''}>Keep</button>
            </div>
          </li>
        {/if}
      {/each}
    </ul>
    <button type="button" class="text-button apps-add" disabled={blocked || registrationBlocked} onclick={() => showAdvanced = true}>Connect another</button>
  {/if}

  {#if pendingApprovals.length}
    <div class="apps-approvals">
      <h4>Needs your review ({pendingApprovals.length})</h4>
      {#each pendingApprovals as approval (approval.id)}
        {@const connector = connectorFor(approval)}
        <article class="apps-approval">
          <strong>{approval.tool}</strong>
          <p>{connector?.name || 'App'} · {approval.state}{expired(approval) && ['pending', 'approved'].includes(approval.state) ? ' · expired' : ''}</p>
          <details>
            <summary>Exact arguments</summary>
            <textarea class="message-source source-review approval-args" aria-label={`Exact arguments for ${approval.tool}`} readonly rows="6" value={approval.argsJSON}></textarea>
          </details>
          {#if ['pending', 'approved'].includes(approval.state) && !expired(approval) && connector && !connector.revoked}
            <label class="approval-check"><input type="checkbox" checked={checked[approval.id] === signature(approval)} disabled={blocked} onchange={event => checked = { ...checked, [approval.id]: event.currentTarget.checked ? signature(approval) : '' }} />I reviewed destination, tool, and arguments.</label>
          {/if}
          <div class="file-actions">
            {#if approval.state === 'pending' && !expired(approval)}
              <button class="primary-button" disabled={blocked || !connector || connector.revoked || checked[approval.id] !== signature(approval)} onclick={() => decide(approval, true)}>Approve</button>
              <button class="danger-button" disabled={blocked} onclick={() => decide(approval, false)}>Deny</button>
            {/if}
            {#if approval.state === 'approved'}
              <button class="danger-button" disabled={!executable(approval)} onclick={() => execute(approval)}>{busy === `execute:${approval.id}` ? 'Running…' : 'Run once'}</button>
            {/if}
          </div>
          {#if approval.state === 'uncertain'}<p class="error-box" role="alert">Outcome unclear — check the app before trying again.</p>{/if}
          {#if results[approval.id]}<details><summary>Result</summary><textarea class="message-source source-review" aria-label={`Result for ${approval.tool}`} readonly rows="6" value={results[approval.id]}></textarea></details>{/if}
        </article>
      {/each}
    </div>
  {/if}

  <details class="apps-advanced" bind:open={showAdvanced}>
    <summary>Add a connector</summary>
    <p class="form-help">Manual HTTPS connector for power users. One-tap apps (X, Gmail, …) are in the plugin list above.</p>
    <form class="apps-register" onsubmit={register} autocomplete="off">
      <label class="form-label" for="connector-name">Name</label>
      <input id="connector-name" class="form-input" bind:value={name} maxlength="120" required disabled={blocked || registrationBlocked} />
      <label class="form-label" for="connector-endpoint">HTTPS endpoint</label>
      <input id="connector-endpoint" type="url" class="form-input" bind:value={endpoint} placeholder="https://service.example/mcp" maxlength="2048" required disabled={blocked || registrationBlocked} />
      <label class="form-label" for="connector-token">Token <span>optional</span></label>
      <input id="connector-token" type={tokenVisible ? 'text' : 'password'} class="form-input" bind:value={bearerToken} autocomplete="new-password" spellcheck="false" maxlength="8192" disabled={blocked || registrationBlocked} />
      <button type="button" class="text-button" aria-controls="connector-token" aria-pressed={tokenVisible} disabled={blocked || registrationBlocked} onclick={() => tokenVisible = !tokenVisible}>{tokenVisible ? 'Hide token' : 'Show token'}</button>
      <button type="submit" class="secondary-button" disabled={blocked || registrationBlocked || !name.trim() || !endpoint.trim()}>{busy === 'register' ? 'Connecting…' : 'Connect'}</button>
      {#if registrationBlocked}<p class="form-help">Registration is off on this server. Ask an admin to allow an endpoint.</p>{/if}
    </form>

    {#each activeConnectors as connector (connector.id)}
      <div class="apps-tooling">
        <div class="apps-tooling-head">
          <strong>{connector.name}</strong>
          <button class="text-button" disabled={blocked} onclick={() => discover(connector)}>{busy === `discover:${connector.id}` ? 'Discovering…' : 'Discover tools'}</button>
        </div>
        {#if tools[connector.id]}
          {#if !tools[connector.id].length}<p class="form-help">No tools reported.</p>
          {:else}
            <label class="form-label" for={`tool-${connector.id}`}>Tool</label>
            <select id={`tool-${connector.id}`} class="form-input" value={selectedTools[connector.id] || ''} disabled={blocked} onchange={event => selectedTools = { ...selectedTools, [connector.id]: event.currentTarget.value }}><option value="">Select…</option>{#each tools[connector.id] as tool (tool.name)}<option value={tool.name}>{tool.name}</option>{/each}</select>
            {@const tool = tools[connector.id].find(item => item.name === selectedTools[connector.id])}
            {#if tool}
              <p class="form-help">{tool.description || 'No description.'}</p>
              <label class="form-label" for={`args-${connector.id}`}>Arguments (JSON)</label>
              <textarea id={`args-${connector.id}`} class="form-input connector-args" rows="4" value={args[connector.id] || '{}'} oninput={event => args = { ...args, [connector.id]: event.currentTarget.value }} spellcheck="false" disabled={blocked}></textarea>
              <button class="secondary-button" disabled={blocked} onclick={() => prepare(connector)}>Prepare approval</button>
            {/if}
          {/if}
        {/if}
      </div>
    {/each}
  </details>
</section>

<style>
  .apps-settings { margin: 8px 0; min-width: 0; }
  .apps-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
  .apps-heading h3 { margin: 0; font: 600 17px/1.3 var(--font); }
  .apps-heading p { margin: 4px 0 0; color: var(--text-2); font: var(--fs-preview)/1.5 var(--font); }
  .apps-notice { margin: 0 0 12px; color: var(--ok-text); font: var(--fs-preview)/1.5 var(--font); }
  .apps-empty { color: var(--text-2); font: 14px/1.5 var(--font); }
  .apps-empty-card { display: grid; justify-items: center; gap: 10px; padding: 24px 16px; border-radius: var(--radius-card); background: var(--bubble); color: var(--text-2); text-align: center; }
  .apps-empty-card p { margin: 0; font: 14px/1.5 var(--font); }
  .apps-list { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
  .apps-row { display: flex; align-items: center; gap: 12px; padding: 10px 14px; border-radius: var(--radius-card); background: var(--bubble); }
  .apps-icon { display: grid; place-items: center; width: 32px; height: 32px; border-radius: var(--radius-avatar); background: var(--page); color: var(--text-2); }
  .apps-copy { min-width: 0; flex: 1; display: grid; gap: 2px; }
  .apps-copy strong { font: 500 15px/1.3 var(--font); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .apps-copy small { color: var(--text-2); font: 13px/1.3 var(--font); }
  .apps-confirm { padding: 8px 14px 12px; list-style: none; }
  .apps-confirm p { margin: 0 0 8px; font: 14px/1.4 var(--font); }
  .apps-add { margin-top: 10px; }
  .apps-approvals { margin-top: 20px; display: grid; gap: 10px; }
  .apps-approvals h4 { margin: 0; font: 600 14.5px/1.3 var(--font); }
  .apps-approval { display: grid; gap: 8px; padding: 14px; border-radius: var(--radius-card); background: var(--bubble); }
  .apps-approval strong { font: 500 15px/1.3 var(--font); }
  .apps-approval > p { margin: 0; color: var(--text-2); font: 13px/1.4 var(--font); }
  .apps-advanced { margin-top: 18px; color: var(--text-2); font: 14px/1.5 var(--font); }
  .apps-advanced summary { cursor: pointer; font-weight: 500; color: var(--text); }
  .apps-register { display: grid; gap: 8px; margin-top: 12px; }
  .apps-tooling { display: grid; gap: 8px; margin-top: 16px; padding-top: 14px; border-top: 1px solid var(--hairline); }
  .apps-tooling-head { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
  .approval-check { font-size: var(--fs-preview); }
  .approval-check input { accent-color: var(--ink); }
  @media (max-width: 520px) { .apps-register .form-input { font-size: 16px; } }
</style>
