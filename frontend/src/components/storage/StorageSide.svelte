<script lang="ts">
  // The column beside the Storage treemap, as in disktree: the entry pointed at or picked (size, share of the scan, files, last write, kind),
  // the largest folders inside the one shown, "Worth a look" (the largest space that could be had back), and the disk's free and used space.
  // It only shows: nothing here deletes or moves a file.
  import Bar from '../monitor/Bar.svelte'
  import { HIDDEN, KIND_LABELS, largestFolders, nodeLabel, pathOf, RECLAIM_LABELS, worthALook } from '../../lib/storageMap.ts'
  import { formatBytes, percentOf } from '../../lib/stats.ts'
  import { relativeTime } from '../../lib/format.ts'
  import type { StorageMap } from '../../lib/types.ts'

  interface Props {
    map: StorageMap
    children: number[][]
    /** The folder the map shows. */
    focus: number
    /** What the column describes: the entry pointed at, else the one picked, else the folder shown. */
    shown: number
    hidden: number
    now: number
    onOpen: (place: number) => void
  }

  let { map, children, focus, shown, hidden, now, onOpen }: Props = $props()
  const MS_PER_SECOND = 1000

  const scanned = $derived(map.nodes[0]?.bytes ?? 0)
  const node = $derived(shown === HIDDEN ? null : map.nodes[shown])
  const bytes = $derived(shown === HIDDEN ? hidden : (node?.bytes ?? 0))
  const share = $derived(percentOf(bytes, shown === HIDDEN ? map.disk.used_bytes : scanned))
  const folders = $derived(largestFolders(map, children, focus))
  const worth = $derived(worthALook(map))
  const worthTotal = $derived(worth.reduce((sum, place) => sum + (map.nodes[place]?.bytes ?? 0), 0))
  const usedShare = $derived(percentOf(map.disk.used_bytes, map.disk.total_bytes))
  const written = (seconds: number | null): string => (seconds === null ? '–' : relativeTime(new Date(seconds * MS_PER_SECOND).toISOString(), now))
</script>

<aside class="st-side" aria-label="Details">
  <section class="block sel" aria-live="polite">
    <h3>Selection</h3>
    {#if shown === HIDDEN}
      <div class="title"><span class="swatch k-hidden"></span>Not readable by the helper</div>
      <p class="path">Used space the helper could not look into: folders only root or another user may open. Their size is known only from the disk's used space.</p>
    {:else if node}
      <div class="title"><span class="swatch k-{node.kind}"></span>{nodeLabel(node)}</div>
      {#if pathOf(map, shown) !== nodeLabel(node)}<p class="path" title={pathOf(map, shown)}>{pathOf(map, shown)}</p>{/if}
    {/if}
    <div class="big nums">{formatBytes(bytes)}</div>
    <span class="share" role="img" aria-label="Share of {shown === HIDDEN ? 'the used space' : 'the scan'}: {Math.round(share)}%"><i style:width="{Math.min(Math.max(share, 0), 100)}%"></i></span>
    <dl class="facts">
      <div><dt>{shown === HIDDEN ? 'Of used space' : 'Of scan'}</dt><dd class="nums">{Math.round(share)}%</dd></div>
      {#if node}
        <div><dt>Files</dt><dd class="nums">{node.files.toLocaleString('en-US')}</dd></div>
        <div><dt>Last write</dt><dd>{written(node.modified)}</dd></div>
        <div><dt>Kind</dt><dd>{KIND_LABELS[node.kind]}</dd></div>
        {#if node.reclaim}<div class="wide"><dt>Could be had back</dt><dd>{RECLAIM_LABELS[node.reclaim]}</dd></div>{/if}
      {/if}
    </dl>
  </section>

  {#if folders.length}
    <section class="block">
      <h3>Folders here</h3>
      <ul class="list">
        {#each folders as place (place)}
          {@const folder = map.nodes[place]}
          {#if folder}
            <li><button type="button" class="row" onclick={() => onOpen(place)}><span class="swatch k-{folder.kind}"></span><span class="nm">{nodeLabel(folder)}</span><span class="sz nums">{formatBytes(folder.bytes)}</span></button></li>
          {/if}
        {/each}
      </ul>
    </section>
  {/if}

  <section class="block">
    <div class="head"><h3>Worth a look</h3>{#if worth.length}<span class="total nums">{formatBytes(worthTotal)}</span>{/if}</div>
    {#if worth.length}
      <ul class="list">
        {#each worth as place (place)}
          {@const entry = map.nodes[place]}
          {#if entry}
            <li>
              <button type="button" class="row two" onclick={() => onOpen(place)} title={pathOf(map, place)}>
                <span class="nm">{nodeLabel(entry)}</span><span class="sz nums">{formatBytes(entry.bytes)}</span>
                <span class="why">{entry.reclaim ? RECLAIM_LABELS[entry.reclaim] : ''}</span>
                <span class="mini share" role="img" aria-label="{nodeLabel(entry)}: {Math.round(percentOf(entry.bytes, worthTotal))}% of the total worth a look"><i style:width="{percentOf(entry.bytes, worthTotal)}%"></i></span>
              </button>
            </li>
          {/if}
        {/each}
      </ul>
    {:else}
      <p class="st-none">Nothing big that could be had back.</p>
    {/if}
  </section>

  <section class="block disk">
    <div class="head"><h3>Disk</h3><span class="root">{map.root}</span></div>
    <div class="big nums">{formatBytes(map.disk.free_bytes)} <small>free</small></div>
    <Bar percent={usedShare} label="Disk {map.root} in use" />
    <div class="ends nums"><span>{formatBytes(map.disk.used_bytes)} used</span><span>{formatBytes(map.disk.total_bytes)} total</span></div>
    {#if hidden > 0}<p class="note nums">{formatBytes(hidden)} of the used space was not readable by the helper.</p>{/if}
  </section>
</aside>

<style>
  .st-side { display: grid; align-content: start; border: 1px solid var(--line); background: var(--surface); min-width: 0; }
  .block { padding: 14px 16px; border-bottom: 1px solid var(--line); display: grid; gap: 8px; min-width: 0; }
  .block:last-child { border-bottom: 0; }
  .disk { background: var(--surface-2); }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .total { font-family: var(--mono); font-size: 12px; font-weight: 700; color: var(--ok); }
  .title { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 16px; min-width: 0; overflow-wrap: anywhere; }
  .path { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); overflow-wrap: anywhere; }
  .big { font-family: var(--mono); font-size: 26px; font-weight: 700; line-height: 1.1; }
  .big small { font-size: 12px; font-weight: 400; color: var(--m60); }
  .facts { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 12px; margin: 4px 0 0; }
  .facts .wide { grid-column: 1 / -1; }
  .facts dt { font-family: var(--mono); font-size: 10px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--m50); }
  .facts dd { margin: 2px 0 0; font-size: 13px; font-weight: 600; }
  .list { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
  .row { width: 100%; display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: 8px; padding: 6px 4px; background: none; border: 0; text-align: left; font: inherit; color: var(--text); cursor: pointer; }
  .row:hover { background: var(--surface-2); }
  .row:focus-visible { outline: 2px solid var(--accent-mark); outline-offset: -2px; }
  .row.two { grid-template-columns: minmax(0, 1fr) auto; row-gap: 2px; }
  .nm { font-weight: 600; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
  .sz { font-family: var(--mono); font-size: 12px; font-weight: 700; }
  .why { font-size: 12px; color: var(--m60); }
  .mini { align-self: center; width: 64px; }
  .share { display: block; height: 7px; background: var(--surface-2); border: 1px solid var(--line); overflow: hidden; }
  .share i { display: block; height: 100%; background: var(--accent-mark); }
  .ends { display: flex; justify-content: space-between; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .note, .st-none { margin: 0; font-size: 12px; color: var(--m60); }
  .root { font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .swatch { width: 10px; height: 10px; flex: none; border: 1px solid var(--store-tile-line); }
  .swatch.k-code { background: var(--store-code-mark); }
  .swatch.k-agent { background: var(--store-agent-mark); }
  .swatch.k-toolchain { background: var(--store-toolchain-mark); }
  .swatch.k-synced { background: var(--store-synced-mark); }
  .swatch.k-git { background: var(--store-git-mark); }
  .swatch.k-media { background: var(--store-media-mark); }
  .swatch.k-documents { background: var(--store-documents-mark); }
  .swatch.k-cache { background: var(--store-cache-mark); }
  .swatch.k-vms { background: var(--store-vms-mark); }
  .swatch.k-other { background: var(--store-other-mark); }
  .swatch.k-hidden { background: var(--store-hidden); }
</style>
