<script lang="ts">
  // The treemap of the Storage tab, as disktree draws it: one tile per folder or file, its area the space it takes, its colour the kind of data,
  // a hatch where the space could be had back. Folders show their contents inside, `depth` levels down. Pressing a folder opens it; pressing a file selects it.
  // The tiles are left out of the Tab order (there can be a thousand of them): the folder list beside the map and the trail above it reach every folder by keyboard.
  import { HIDDEN, layoutTiles, nodeLabel, type Tile } from '../../lib/storageMap.ts'
  import { formatBytes } from '../../lib/stats.ts'
  import type { StorageMap } from '../../lib/types.ts'

  interface Props {
    map: StorageMap
    children: number[][]
    focus: number
    selected: number | null
    depth: number
    hidden: number
    onOpen: (place: number) => void
    onSelect: (place: number) => void
    onHover: (place: number | null) => void
  }

  let { map, children, focus, selected, depth, hidden, onOpen, onSelect, onHover }: Props = $props()
  let width = $state(0)
  let height = $state(0)
  const tiles = $derived(width > 0 && height > 0 ? layoutTiles(map, children, focus, { x: 0, y: 0, w: width, h: height }, depth) : [])
  const focusName = $derived(map.nodes[focus] ? nodeLabel(map.nodes[focus]) : map.root)

  /** Names need room: one line from this size, the size under it from a bit taller. */
  const NAME_MIN_W = 34
  const NAME_MIN_H = 15
  const SIZE_MIN_H = 30

  const bytesOf = (tile: Tile): number => (tile.node === HIDDEN ? hidden : (map.nodes[tile.node]?.bytes ?? 0))
  const nameOf = (tile: Tile): string => {
    const node = map.nodes[tile.node]
    return tile.node === HIDDEN || !node ? 'Not readable by the helper' : nodeLabel(node)
  }
  const kindClass = (tile: Tile): string => (tile.node === HIDDEN ? 'k-hidden' : `k-${map.nodes[tile.node]?.kind ?? 'other'}`)
  const hatched = (tile: Tile): boolean => tile.node !== HIDDEN && (map.nodes[tile.node]?.reclaim ?? null) !== null
  const isRest = (tile: Tile): boolean => map.nodes[tile.node]?.type === 'rest'

  function press(tile: Tile) {
    if (tile.node !== HIDDEN && map.nodes[tile.node]?.type === 'dir' && (children[tile.node]?.length ?? 0) > 0) onOpen(tile.node)
    else onSelect(tile.node)
  }
</script>

<div class="mosaic" bind:clientWidth={width} bind:clientHeight={height} role="group" aria-label="Treemap of {focusName}" onmouseleave={() => onHover(null)}>
  {#each tiles as tile (tile.node)}
    {@const showName = tile.w >= NAME_MIN_W && (tile.header > 0 || tile.h >= NAME_MIN_H)}
    <button
      type="button"
      tabindex="-1"
      class="tile {kindClass(tile)}"
      class:hatch={hatched(tile)}
      class:rest={isRest(tile)}
      class:open={tile.header > 0}
      class:sel={selected === tile.node}
      style="left:{tile.x}px;top:{tile.y}px;width:{tile.w}px;height:{tile.h}px"
      title="{nameOf(tile)} · {formatBytes(bytesOf(tile))}"
      onclick={() => press(tile)}
      onmouseenter={() => onHover(tile.node)}
    >
      {#if showName}
        <span class="label" class:strip={tile.header > 0} style={tile.header > 0 ? `height:${tile.header}px` : ''}>
          <span class="nm">{nameOf(tile)}</span>
          {#if tile.header > 0 || tile.h >= SIZE_MIN_H}<span class="sz">{formatBytes(bytesOf(tile))}</span>{/if}
        </span>
      {/if}
    </button>
  {/each}
</div>

<style>
  .mosaic { position: relative; height: clamp(360px, 62vh, 620px); border: 1px solid var(--line-strong); background: var(--surface-2); overflow: hidden; }
  .tile { position: absolute; box-sizing: border-box; margin: 0; padding: 0; border: 1px solid var(--store-tile-line); background-color: var(--store-other); text-align: left; cursor: pointer; overflow: hidden; font: inherit; color: var(--text); display: block; }
  .tile.hatch { background-image: repeating-linear-gradient(135deg, transparent 0 5px, var(--store-hatch) 5px 6px); }
  .tile.rest { opacity: 0.78; }
  .tile:hover { border-color: var(--line-strong); }
  .tile.sel { outline: 2px solid var(--accent-mark); outline-offset: -2px; z-index: 1; }
  /* A button centres what it holds; the name belongs at the top-left, above where a folder's contents start. */
  .label { position: absolute; top: 0; left: 0; right: 0; display: flex; flex-direction: column; padding: 2px 4px; min-width: 0; pointer-events: none; }
  .label.strip { flex-direction: row; align-items: baseline; gap: 6px; padding: 1px 4px; }
  .nm { font-family: var(--mono); font-size: 11px; font-weight: 700; line-height: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
  .sz { font-family: var(--mono); font-size: 10px; line-height: 13px; color: var(--m60); white-space: nowrap; }
  .strip .sz { margin-left: auto; }
  .k-code { background-color: var(--store-code); }
  .k-agent { background-color: var(--store-agent); }
  .k-toolchain { background-color: var(--store-toolchain); }
  .k-synced { background-color: var(--store-synced); }
  .k-git { background-color: var(--store-git); }
  .k-media { background-color: var(--store-media); }
  .k-documents { background-color: var(--store-documents); }
  .k-cache { background-color: var(--store-cache); }
  .k-vms { background-color: var(--store-vms); }
  .k-other { background-color: var(--store-other); }
  .k-hidden { background-color: var(--store-hidden); background-image: repeating-linear-gradient(45deg, transparent 0 7px, var(--store-hatch) 7px 8px); }
</style>
