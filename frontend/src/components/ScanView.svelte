<script lang="ts">
  import { onMount } from 'svelte'
  import { ApiError, latestScan, scanSetup, startScan } from '../lib/api.ts'
  import Owl from './Owl.svelte'
  import { relativeTime, sourceName, sourceProblem } from '../lib/format.ts'
  import { rowStatus } from '../lib/scanRows.ts'
  import type { Machine, Scan, ScanSetup } from '../lib/types.ts'

  const POLL_MS = 1500

  let { machines, onConnect }: { machines: Machine[]; onConnect: (host?: string) => void } = $props()
  let setup = $state<ScanSetup | null>(null)
  let scan = $state<Scan | null>(null)
  let failure = $state('')
  let timer: ReturnType<typeof setTimeout> | undefined
  const running = $derived(scan?.state === 'running')
  // "Router not set up" is normal (the router is optional) and the missing network scan is explained above the table, so neither is repeated here.
  const EXPLAINED = new Set(['not_configured', 'missing'])
  const sourceNotes = $derived(
    Object.entries(scan?.sources ?? {})
      .filter(([, value]) => !EXPLAINED.has(value))
      .map(([key, value]) => ({ key, problem: sourceProblem(value) }))
      .filter((note) => note.problem),
  )

  const isGateway = (ip: string) => !!setup?.gateway && setup.gateway === ip
  const isSelf = (ip: string) => !!setup?.own_addresses?.includes(ip)

  /** Opening the page shows the last scan at once (it is kept), and follows one that is still running. A new scan only starts when asked for. */
  async function load() {
    try {
      setup = await scanSetup()
    } catch (error) {
      failure = error instanceof ApiError ? error.message : 'Something went wrong.'
      return
    }
    try {
      scan = await latestScan()
    } catch (error) {
      showFailure(error)
      return
    }
    if (running) poll()
  }

  const showFailure = (error: unknown) => (failure = error instanceof ApiError ? error.message : 'Something went wrong.')

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
    scan = { id: '', state: 'running', results: [], sources: {} }
    try {
      await startScan()
    } catch (error) {
      // A scan another tab started is still the one to follow.
      if (!(error instanceof ApiError && error.code === 'scan_running')) {
        scan = null
        showFailure(error)
        return
      }
    }
    poll()
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
        {#if setup?.subnet}Looks at <span class="mono">{setup.subnet}</span> only.
        {:else}Looking for the network…{/if}
      </p>
      {#if scan?.finished_at && !running}<p class="muted">Last scan {relativeTime(scan.finished_at)}. A computer's address changed? Scan again.</p>{/if}
    </div>
    <button class="btn green" type="button" onclick={begin} disabled={running || !setup?.subnet}>{running ? 'Scanning…' : scan ? 'Scan again' : 'Scan now'}</button>
  </div>

  {#if setup && !setup.nmap_available}
    <p class="note">The network scan is not available here, so only the router's list is used.</p>
  {/if}
  {#each sourceNotes as note (note.key)}
    <p class="note">{sourceName(note.key)} {note.problem}.</p>
  {/each}
  {#if failure}<p class="note bad" role="alert">{failure}</p>{/if}

  {#if scan?.state === 'failed'}
    <p class="note bad">The scan could not use any source. Check the notes above.</p>
  {:else if !scan && setup?.subnet}
    <div class="none"><Owl name="emptyMachines" /><p class="muted">Nothing scanned yet. Press Scan now to look at the network.</p></div>
  {:else if scan && scan.state === 'done' && scan.results.length === 0}
    <div class="none"><Owl name="emptyMachines" /><p class="muted">The scan found nothing on this network.</p></div>
  {:else if running}
    <div class="none"><Owl name="loading" /><p class="muted">Looking at the network…</p></div>
  {:else if scan?.results?.length}
    <div class="table" role="table" aria-label="Devices found">
      <div class="head" role="row"><span>Address</span><span>Name</span><span>MAC address</span><span>Status</span></div>
      {#each scan.results as row (row.id)}
        {@const status = rowStatus(row, machines, { gateway: isGateway(row.ip) })}
        <div class="row" role="row">
          <span class="mono" data-label="Address">{row.ip}</span>
          <span data-label="Name">{row.hostname ?? '–'}{#if row.vendor}<span class="muted vendor">· {row.vendor}</span>{/if}</span>
          <span class="mono" data-label="MAC address">{row.mac ?? '–'}</span>
          <span class="status" data-label="Status">
            {#if isSelf(row.ip)}<span class="badge">This computer</span> {/if}
            {#if status.kind === 'router'}<span class="badge">Router</span>
            {:else if status.kind === 'added'}<span class="badge ok">Added</span> <strong>{status.name}</strong>
            {:else if status.kind === 'agent'}<span class="badge ok">Agent running</span>
            {:else}
              <button class="btn green sm" type="button" onclick={() => onConnect(row.ip)} aria-label="Add {row.ip}">Add</button>
            {/if}
          </span>
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .scan { display: grid; gap: 16px; }
  .none { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; text-align: center; min-height: calc(100svh - 300px); }
  .top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; flex-wrap: wrap; }
  h2 { font-size: 20px; }
  .note { padding: 10px 14px; border-radius: 8px; background: var(--warn-bg); color: var(--warn); }
  .note.bad { background: var(--danger-bg); color: var(--danger); }
  .table { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
  .head, .row { display: grid; grid-template-columns: 140px minmax(140px, 1fr) 170px minmax(240px, 1.3fr); gap: 12px; align-items: center; padding: 10px 16px; }
  .head { background: var(--surface-2); color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
  .row { border-top: 1px solid var(--line); }
  .vendor { margin-left: 6px; }
  .status { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .badge { padding: 2px 9px; border-radius: 999px; background: var(--surface-2); border: 1px solid var(--line); color: var(--muted); font-size: 12px; font-weight: 600; }
  .badge.ok { color: var(--ok); }
  @media (max-width: 900px) {
    .head { display: none; }
    .row { grid-template-columns: 1fr; padding: 14px; gap: 6px; }
    .row > span[data-label]::before { content: attr(data-label) ': '; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
  }
</style>
