<script>
  import { onMount } from 'svelte'
  import { ApiError, addFromScan, latestScan, scanSetup, startScan } from '../lib/api.js'
  import { sourceName, sourceProblem, suggestName, nameProblem } from '../lib/format.js'
  import Dialog from './Dialog.svelte'
  import TokenList from './TokenList.svelte'

  const POLL_MS = 1500

  let setup = $state(null)
  let scan = $state(null)
  let failure = $state('')
  let picked = $state({})
  let names = $state({})
  let adding = $state(false)
  let invites = $state(null)
  let timer = null
  const running = $derived(scan?.state === 'running')
  const chosen = $derived((scan?.results ?? []).filter((row) => picked[row.id]))
  const problems = $derived(chosen.map((row) => nameProblem(names[row.id] ?? '')).filter(Boolean))
  // "Not set up" and "not installed" are already explained above the table, so they are not repeated here.
  const EXPLAINED = new Set(['not_configured', 'missing'])
  const sourceNotes = $derived(
    Object.entries(scan?.sources ?? {})
      .filter(([, value]) => !EXPLAINED.has(value))
      .map(([key, value]) => ({ key, problem: sourceProblem(value) }))
      .filter((note) => note.problem),
  )

  async function load() {
    try {
      setup = await scanSetup()
      scan = await latestScan()
      if (running) poll()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  function poll() {
    clearTimeout(timer)
    timer = setTimeout(async () => {
      try {
        scan = await latestScan()
      } catch {
        failure = 'Lost contact with the Root.'
      }
      if (running) poll()
    }, POLL_MS)
  }

  async function begin() {
    failure = ''
    picked = {}
    try {
      await startScan()
      scan = { ...(scan ?? {}), state: 'running', results: [], sources: {} }
      poll()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    }
  }

  function toggle(row) {
    picked[row.id] = !picked[row.id]
    if (picked[row.id] && !names[row.id]) names[row.id] = suggestName(row.hostname, row.ip)
  }

  async function addChosen() {
    adding = true
    failure = ''
    try {
      const reply = await addFromScan(scan.id, chosen.map((row) => ({ result_id: row.id, name: names[row.id] })))
      invites = reply.invites
      picked = {}
      await load()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
    } finally {
      adding = false
    }
  }

  onMount(() => {
    load()
    return () => clearTimeout(timer)
  })
</script>

<section class="scan">
  <div class="top">
    <div>
      <h2>Find machines</h2>
      <p class="muted">
        {#if setup?.subnet}Looks at <span class="mono">{setup.subnet}</span> only, through the router and nmap. Nothing is added until you choose it.
        {:else}Looking for the network…{/if}
      </p>
    </div>
    <button class="btn green" type="button" onclick={begin} disabled={running || !setup?.subnet}>{running ? 'Scanning…' : 'Scan now'}</button>
  </div>

  {#if setup && !setup.router_configured}
    <p class="note">The router is not set up, so MAC addresses and names may be missing. Add ROUTER_URL, ROUTER_USER and ROUTER_PASSWORD to the Root's env file.</p>
  {/if}
  {#if setup && !setup.nmap_available}
    <p class="note">nmap was not found on the Root machine, so only the router's list is used.</p>
  {/if}
  {#each sourceNotes as note (note.key)}
    <p class="note">{sourceName(note.key)} {note.problem}.</p>
  {/each}
  {#if failure}<p class="note bad" role="alert">{failure}</p>{/if}

  {#if scan?.state === 'failed'}
    <p class="note bad">The scan could not use any source. Check the notes above.</p>
  {:else if scan && scan.state === 'done' && scan.results.length === 0}
    <p class="muted">The scan found nothing on this network.</p>
  {:else if scan?.results?.length}
    <div class="table" role="table" aria-label="Devices found">
      <div class="head" role="row"><span></span><span>Address</span><span>Name</span><span>MAC address</span><span>Seen by</span><span>Status</span></div>
      {#each scan.results as row (row.id)}
        <div class="row" role="row">
          <span class="pick">
            <input type="checkbox" checked={!!picked[row.id]} disabled={!!row.machine} onchange={() => toggle(row)} aria-label="Pick {row.ip}" />
          </span>
          <span class="mono" data-label="Address">{row.ip}</span>
          <span data-label="Name">{row.hostname ?? '–'}{#if row.vendor}<span class="muted vendor">· {row.vendor}</span>{/if}</span>
          <span class="mono" data-label="MAC address">{row.mac ?? '–'}</span>
          <span class="tags" data-label="Seen by">{#each row.seen_by as source (source)}<span class="tag">{sourceName(source)}</span>{/each}</span>
          <span data-label="Status">
            {#if row.machine}Enrolled as <strong>{row.machine}</strong>
            {:else if row.agent_port_open}<span class="ok">Agent answering</span>
            {:else}<span class="muted">Unknown device</span>{/if}
          </span>
          {#if picked[row.id]}
            <label class="name">Machine name
              <input bind:value={names[row.id]} autocomplete="off" spellcheck="false" maxlength="63" aria-label="Machine name for {row.ip}" />
            </label>
          {/if}
        </div>
      {/each}
    </div>
    <div class="actions">
      <span class="muted">{chosen.length} picked</span>
      <button class="btn green" type="button" disabled={adding || chosen.length === 0 || problems.length > 0} onclick={addChosen}>
        {adding ? 'Creating…' : 'Create enrollment tokens'}
      </button>
    </div>
    {#if problems.length}<p class="note bad">{problems[0]}</p>{/if}
  {/if}
</section>

<Dialog open={invites !== null} title="Enrollment tokens" onClose={() => (invites = null)}>
  {#if invites}
    <p>Each token works once, only from the address that was scanned, and is not shown again. Use it when you install the Agent on that machine.</p>
    <TokenList {invites} />
    <div class="done"><button class="btn green" type="button" onclick={() => (invites = null)}>Done</button></div>
  {/if}
</Dialog>

<style>
  .scan { display: grid; gap: 16px; }
  .top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; flex-wrap: wrap; }
  h2 { font-size: 20px; }
  .note { padding: 10px 14px; border-radius: 8px; background: var(--warn-bg); color: var(--warn); }
  .note.bad { background: var(--danger-bg); color: var(--danger); }
  .table { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
  .head, .row { display: grid; grid-template-columns: 40px 140px minmax(160px, 1.4fr) 170px minmax(150px, 1fr) minmax(160px, 1fr); gap: 12px; align-items: center; padding: 10px 16px; }
  .head { background: var(--surface-2); color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
  .row { border-top: 1px solid var(--line); }
  .pick input { width: 18px; height: 18px; }
  .tags { display: flex; gap: 6px; flex-wrap: wrap; }
  .tag { padding: 0 7px; border-radius: 6px; background: var(--surface-2); border: 1px solid var(--line); font-size: 12px; font-weight: 600; }
  .vendor { margin-left: 6px; }
  .ok { color: var(--ok); font-weight: 600; }
  .name { grid-column: 2 / -1; display: grid; gap: 4px; font-size: 13px; color: var(--muted); }
  .name input { min-height: 38px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); max-width: 360px; }
  .actions { display: flex; align-items: center; justify-content: flex-end; gap: 14px; }
  .done { display: flex; justify-content: flex-end; }
  @media (max-width: 900px) {
    .head { display: none; }
    .row { grid-template-columns: 32px 1fr; padding: 14px; gap: 6px 10px; }
    .row > span:not(.pick) { grid-column: 2; }
    .row > span[data-label]::before { content: attr(data-label) ': '; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
    .name { grid-column: 2; }
  }
</style>
