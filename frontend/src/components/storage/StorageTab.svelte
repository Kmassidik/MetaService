<script lang="ts">
  // The Storage tab of a machine's page: what fills the machine's disk, drawn the way disktree draws it (github.com/tobi/disktree).
  // The helper scans in the background at the lowest priority; this page asks for the last map once, asks again every 2 seconds only while a scan runs,
  // and starts the first scan itself when the machine has never been scanned. Rescan asks for a fresh one. Read only: nothing here deletes a file.
  import { untrack } from 'svelte'
  import StorageSide from './StorageSide.svelte'
  import StorageTreemap from './StorageTreemap.svelte'
  import { getMachineStorage, scanMachineStorage } from '../../lib/api.ts'
  import { childrenOf, crumbsOf, DEFAULT_DEPTH, hiddenBytes, HIDDEN, KIND_LABELS, LEGEND_KINDS, MAX_DEPTH, MIN_DEPTH, nodeLabel } from '../../lib/storageMap.ts'
  import { formatBytes } from '../../lib/stats.ts'
  import { relativeTime } from '../../lib/format.ts'
  import { browserEnvironment, startPolling } from '../../lib/statsPoll.ts'
  import type { Machine, MachineStorageReply } from '../../lib/types.ts'

  const SCANNING_POLL_MS = 2000
  const FAILED_POLL_MS = 5000

  let { machine, now }: { machine: Machine; now: number } = $props()
  const id = $derived(machine.id)
  let reply = $state<MachineStorageReply | null>(null)
  let failed = $state(false)
  let asking = $state(false)
  let askFailed = $state(false)
  let firstScanAsked = false
  let focus = $state(0)
  let picked = $state<number | null>(null)
  let pointed = $state<number | null>(null)
  let depth = $state(DEFAULT_DEPTH)

  const storage = $derived(reply?.storage ?? null)
  const map = $derived(storage?.map ?? null)
  const children = $derived(map ? childrenOf(map.nodes) : [])
  const hidden = $derived(map ? hiddenBytes(map) : 0)
  const trail = $derived(map ? crumbsOf(map.nodes, focus) : [])
  const shown = $derived(pointed ?? picked ?? focus)
  const scanning = $derived(storage?.scanning ?? false)

  async function load(current: () => boolean) {
    try {
      const next = await getMachineStorage(id)
      if (!current()) return
      reply = next
      failed = false
      if (next.storage?.map && focus >= next.storage.map.nodes.length) focus = 0
      if (next.state === 'online' && next.storage && !next.storage.scanning && !next.storage.map && !next.storage.error && !firstScanAsked) {
        firstScanAsked = true
        await scan()
      }
    } catch {
      if (current()) failed = true
    }
  }

  async function scan() {
    asking = true
    askFailed = false
    try {
      reply = await scanMachineStorage(id)
    } catch {
      askFailed = true
    } finally {
      asking = false
    }
  }

  // One read when the tab opens; more only while a scan runs (or after a failed read), never while the browser tab is hidden.
  // A scan that starts or ends starts a new run, because a parked run (no scan, nothing to wait for) has no timer left to wake it.
  $effect(() => {
    void id
    void scanning
    return untrack(() => {
      let running = true
      const stop = startPolling(browserEnvironment(), () => (failed ? FAILED_POLL_MS : scanning ? SCANNING_POLL_MS : null), () => load(() => running))
      return () => {
        running = false
        stop()
      }
    })
  })

  function open(place: number) {
    if (!map || place === HIDDEN) return
    const node = map.nodes[place]
    if (!node) return
    if (node.type === 'dir' && (children[place]?.length ?? 0) > 0) {
      focus = place
      picked = null
    } else {
      focus = node.parent >= 0 ? node.parent : 0
      picked = place
    }
    pointed = null
  }

  function up() {
    if (!map || focus === 0) return
    picked = focus
    focus = Math.max(map.nodes[focus]?.parent ?? 0, 0)
  }

  function onKey(event: KeyboardEvent) {
    if (event.key === 'Escape' || event.key === 'Backspace') {
      event.preventDefault()
      up()
    }
  }
</script>

<section class="storage" aria-label="Storage">
  <div class="bar">
    <div class="totals">
      {#if map}
        <b class="nums">{formatBytes(map.nodes[0]?.bytes ?? 0)}</b>
        <span class="nums">· {(map.nodes[0]?.files ?? 0).toLocaleString('en-US')} files</span>
        {#if map.unreadable > 0}<span class="warn nums">· {map.unreadable.toLocaleString('en-US')} unreadable</span>{/if}
        <span>· scanned {relativeTime(map.finished_at, now)} in {Math.round(map.seconds)} s</span>
      {:else if reply?.state === 'online'}
        <span>No map of this disk yet.</span>
      {/if}
      {#if scanning && storage?.progress}
        <span class="busy nums">Scanning… {storage.progress.entries.toLocaleString('en-US')} entries, {formatBytes(storage.progress.bytes)} so far</span>
      {/if}
    </div>
    <div class="tools">
      {#if map}
        <div class="depth" title="How many levels are drawn at once">
          <span>Depth <b class="nums">{depth}</b></span>
          <button type="button" class="btn line sm" aria-label="Draw fewer levels" disabled={depth <= MIN_DEPTH} onclick={() => (depth -= 1)}>−</button>
          <button type="button" class="btn line sm" aria-label="Draw more levels" disabled={depth >= MAX_DEPTH} onclick={() => (depth += 1)}>+</button>
        </div>
      {/if}
      {#if reply?.state === 'online'}
        <button type="button" class="btn line sm" disabled={scanning || asking} onclick={scan}>{scanning ? 'Scanning…' : 'Rescan'}</button>
      {/if}
    </div>
  </div>

  {#if failed && !reply}
    <p class="note">The storage map could not be read. Trying again…</p>
  {:else if reply?.state === 'old_helper'}
    <p class="note">This machine's helper cannot map its disk yet. Update the helper on the Environment tab.</p>
  {:else if reply?.state === 'offline'}
    <p class="note">The machine is offline or did not answer, so its disk cannot be read now.</p>
  {/if}
  {#if askFailed}<p class="note">The scan could not be started. Try Rescan again.</p>{/if}
  {#if storage?.error}<p class="note">The last scan failed: {storage.error}</p>{/if}

  {#if map}
    <nav class="trail" aria-label="Where you are">
      {#each trail as place, index (place)}
        {@const node = map.nodes[place]}
        {#if index > 0}<span class="sep" aria-hidden="true">›</span>{/if}
        {#if index === trail.length - 1}
          <span aria-current="location" class="here">{index === 0 ? map.root : node ? nodeLabel(node) : ''}</span>
        {:else}
          <button type="button" onclick={() => open(place)}>{index === 0 ? map.root : node ? nodeLabel(node) : ''}</button>
        {/if}
      {/each}
    </nav>
    <ul class="legend" aria-label="Colours">
      {#each LEGEND_KINDS as kind (kind)}<li><span class="sw k-{kind}"></span>{KIND_LABELS[kind]}</li>{/each}
      <li><span class="sw hatch"></span>Could be had back</li>
      {#if hidden > 0}<li><span class="sw k-hidden"></span>Not readable</li>{/if}
    </ul>
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="st-body" onkeydown={onKey}>
      <StorageTreemap {map} {children} {focus} selected={picked} {depth} {hidden} onOpen={open} onSelect={(place) => (picked = place)} onHover={(place) => (pointed = place)} />
      <StorageSide {map} {children} {focus} {shown} {hidden} {now} onOpen={open} />
    </div>
  {:else if scanning}
    <div class="first" role="status">
      <b>Mapping this disk for the first time.</b>
      <span>The helper walks the whole disk at the lowest priority, so VMs on this machine are not slowed. A big disk can take a few minutes.</span>
      <span class="sweep" aria-hidden="true"><i></i></span>
    </div>
  {/if}
</section>

<style>
  .storage { display: grid; gap: 12px; }
  .bar { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
  .totals { display: flex; flex-wrap: wrap; gap: 6px; align-items: baseline; font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .totals b { color: var(--text); font-size: 13px; }
  .warn { color: var(--warn); }
  .busy { color: var(--ok); font-weight: 700; }
  .tools { display: flex; gap: 10px; align-items: center; }
  .depth { display: flex; gap: 4px; align-items: center; font-family: var(--mono); font-size: 12px; }
  .depth span { margin-right: 4px; }
  .depth .btn { min-width: 28px; padding: 5px 8px; }
  .note { margin: 0; padding: 10px 12px; border: 1px solid var(--warn-note-line); background: var(--warn-note-bg); color: var(--m70); font-size: 13px; }
  .trail { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; font-family: var(--mono); font-size: 12px; }
  .trail button { background: none; border: 0; padding: 2px 4px; font: inherit; color: var(--text); text-decoration: underline; text-underline-offset: 2px; cursor: pointer; }
  .trail .here { font-weight: 700; padding: 2px 4px; }
  .sep { color: var(--m50); }
  .legend { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px 14px; font-size: 12px; color: var(--m60); }
  .legend li { display: flex; gap: 6px; align-items: center; }
  .sw { width: 10px; height: 10px; border: 1px solid var(--store-tile-line); display: inline-block; }
  .sw.hatch { background: repeating-linear-gradient(135deg, var(--surface) 0 2px, var(--m50) 2px 3px); }
  .sw.k-code { background: var(--store-code-mark); }
  .sw.k-agent { background: var(--store-agent-mark); }
  .sw.k-toolchain { background: var(--store-toolchain-mark); }
  .sw.k-synced { background: var(--store-synced-mark); }
  .sw.k-git { background: var(--store-git-mark); }
  .sw.k-media { background: var(--store-media-mark); }
  .sw.k-documents { background: var(--store-documents-mark); }
  .sw.k-cache { background: var(--store-cache-mark); }
  .sw.k-vms { background: var(--store-vms-mark); }
  .sw.k-hidden { background: var(--store-hidden); }
  .st-body { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 12px; align-items: start; }
  .first { display: grid; gap: 8px; padding: 18px; border: 1px solid var(--line); background: var(--surface); font-size: 13px; color: var(--m60); }
  .first b { color: var(--text); }
  .sweep { display: block; height: 7px; border: 1px solid var(--line); background: var(--surface-2); overflow: hidden; }
  .sweep i { display: block; width: 30%; height: 100%; background: var(--accent-mark); animation: sweep 1.4s ease-in-out infinite alternate; }
  @keyframes sweep { from { margin-left: 0; } to { margin-left: 70%; } }
  @media (prefers-reduced-motion: reduce) { .sweep i { animation: none; width: 100%; } }
  @media (max-width: 980px) { .st-body { grid-template-columns: minmax(0, 1fr); } }
</style>
