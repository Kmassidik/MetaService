<script lang="ts">
  import { layout, machineHrefFor, probe3dIcons, iconPath } from '../lib/machineMap.ts'
  import type { Machine } from '../lib/types.ts'
  import type { MapNode } from '../lib/machineMap.ts'

  let { machines, hub }: { machines: Machine[]; hub: string } = $props()
  let version = $state(0)
  $effect(() => {
    void probe3dIcons(machines.map((m) => m.id)).then(() => version++)
  })
  const base = $derived.by(() => {
    void version
    return layout(machines, hub)
  })

  // --- view transform: pan + zoom ---
  const MIN_SCALE = 0.4
  const MAX_SCALE = 3
  let scale = $state(1)
  let offsetX = $state(0)
  let offsetY = $state(0)

  function zoomAt(factor: number, cx: number, cy: number): void {
    const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * factor))
    if (next === scale) return
    offsetX = cx - ((cx - offsetX) * next) / scale
    offsetY = cy - ((cy - offsetY) * next) / scale
    scale = next
  }

  function onWheel(event: WheelEvent): void {
    event.preventDefault()
    const rect = canvasEl!.getBoundingClientRect()
    zoomAt(event.deltaY < 0 ? 1.12 : 1 / 1.12, event.clientX - rect.left, event.clientY - rect.top)
  }

  // --- node drag vs canvas pan vs click-vs-double-click ---
  type DragMode = 'none' | 'pan' | 'node'
  let mode: DragMode = $state('none')
  let startPointer = $state({ x: 0, y: 0 })
  let startOffset = $state({ x: 0, y: 0 })
  let dragNodeId: string | null = $state(null)
  let nodeStart = $state({ x: 0, y: 0 })
  let moved = false
  let selectedId = $state<string | null>(null)
  const HUB_NODE_ID = '__hub__'
  const STATE_LABELS: Record<MapNode['state'], string> = { online: 'online', setup: 'needs setup', offline: 'offline' }
  const TABLE_ROW_ID_PREFIX = 'maprow-'
  const tableNodes = $derived(base.nodes.filter((n) => n.id !== HUB_NODE_ID))

  function rowEl(nodeId: string): Element | null {
    return document.getElementById(`${TABLE_ROW_ID_PREFIX}${nodeId}`)
  }

  function scrollToRow(nodeId: string): void {
    rowEl(nodeId)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }

  let lastClickTime = 0
  let lastClickId: string | null = null
  function selectRow(nodeId: string): void {
    lastClickTime = 0
    lastClickId = null
    selectedId = nodeId
  }
  let positions = $state<Record<string, { x: number; y: number }>>(loadPositions())

  function loadPositions(): Record<string, { x: number; y: number }> {
    try {
      return JSON.parse(localStorage.getItem('ms-map-positions') ?? '{}') as Record<string, { x: number; y: number }>
    } catch {
      return {}
    }
  }

  function savePosition(id: string, x: number, y: number): void {
    const all = loadPositions()
    all[id] = { x, y }
    localStorage.setItem('ms-map-positions', JSON.stringify(all))
  }

  function canvasPos(event: PointerEvent): { x: number; y: number } {
    const rect = canvasEl!.getBoundingClientRect()
    return { x: event.clientX - rect.left, y: event.clientY - rect.top }
  }

  function nodePos(nodeId: string, basePos: { x: number; y: number }): { x: number; y: number } {
    return positions[nodeId] ?? basePos
  }

  let canvasEl: SVGSVGElement | undefined = $state()

  function onPointerDown(event: PointerEvent, nodeId?: string): void {
    (event.currentTarget as Element).setPointerCapture?.(event.pointerId)
    const p = canvasPos(event)
    startPointer = p
    mode = nodeId ? 'node' : 'pan'
    moved = false
    if (nodeId) {
      dragNodeId = nodeId
      const n = base.nodes.find((n) => n.id === nodeId)
      const start = n ? nodePos(nodeId, { x: n.x, y: n.y }) : { x: 0, y: 0 }
      nodeStart = start
    } else {
      startOffset = { x: offsetX, y: offsetY }
    }
  }

  function onPointerMove(event: PointerEvent): void {
    if (mode === 'none') return
    const p = canvasPos(event)
    const dx = p.x - startPointer.x
    const dy = p.y - startPointer.y
    if (Math.abs(dx) + Math.abs(dy) > 4) moved = true
    if (mode === 'pan') {
      offsetX = startOffset.x + dx
      offsetY = startOffset.y + dy
    } else if (mode === 'node' && dragNodeId) {
      positions[dragNodeId] = { x: nodeStart.x + dx / scale, y: nodeStart.y + dy / scale }
    }
  }

  function onPointerUp(nodeId: string | undefined, event: PointerEvent): void {
    void event
    if (mode === 'node' && dragNodeId) {
      const pos = positions[dragNodeId]
      if (pos) savePosition(dragNodeId, pos.x, pos.y)
    }
    const wasMoved = moved
    mode = 'none'
    dragNodeId = null
    if (wasMoved || !nodeId) return
    // click discrimination: single click selects, double click (two clicks within 350ms on the same node) opens
    const now = Date.now()
    if (lastClickId === nodeId && now - lastClickTime < 350) {
      lastClickTime = 0
      lastClickId = null
      location.hash = machineHrefFor({ id: nodeId, icon: 'cloud', x: 0, y: 0, label: nodeId, subtitle: '', state: 'online', machineId: nodeId })
      return
    }
    lastClickTime = now
    lastClickId = nodeId
    selectedId = nodeId
    scrollToRow(nodeId)
  }

  function resetView(): void {
    scale = 1
    offsetX = 0
    offsetY = 0
  }
</script>

<svg
  bind:this={canvasEl}
  viewBox="0 0 960 560"
  class="map"
  class:grabbing={mode === 'pan'}
  role="img"
  aria-label="Machines map"
  onwheel={onWheel}
  onpointerdown={(e) => onPointerDown(e)}
  onpointermove={onPointerMove}
  onpointerup={(e) => onPointerUp(undefined, e)}
  onpointerleave={() => (mode = 'none')}
>
  <g transform="translate({offsetX},{offsetY}) scale({scale})">
    {#each base.edges as edge}
      <line class="edge edge-{edge.kind}" x1={edge.from.x} y1={edge.from.y} x2={edge.to.x} y2={edge.to.y} />
    {/each}
    {#each base.nodes as node (node.id)}
      {@const pos = nodePos(node.id, { x: node.x, y: node.y })}
      <g
        class="node node-{node.state}"
        class:selected={selectedId === node.id}
        transform="translate({pos.x},{pos.y})"
        role="link"
        tabindex="0"
        onpointerdown={(e) => { e.stopPropagation(); onPointerDown(e, node.id) }}
        onpointerup={(e) => { e.stopPropagation(); onPointerUp(node.id, e) }}
        onkeydown={(e) => e.key === 'Enter' && (location.hash = machineHrefFor(node))}
      >
        <rect class="tile" x="-34" y="-30" width="68" height="68" rx="8" />
        <image href={iconPath(node)} x="-24" y="-24" width="48" height="48" />
        <text class="label" y="52">{node.label}</text>
        <text class="sub" y="67">{node.subtitle}</text>
        <circle class="statedot" cx="24" cy="-24" r="5" />
      </g>
    {/each}
  </g>
</svg>

<div class="mapcontrols">
  <button type="button" aria-label="Zoom in" onclick={() => zoomAt(1.25, 480, 280)}>＋</button>
  <button type="button" aria-label="Zoom out" onclick={() => zoomAt(1 / 1.25, 480, 280)}>−</button>
  <button type="button" aria-label="Reset view" onclick={resetView}>⌂</button>
  <span class="zoomlevel">{Math.round(scale * 100)}%</span>
</div>

<div class="machinetable-wrap">
  <table class="machinetable" aria-label="Machines">
    <thead>
      <tr><th class="col-icon"></th><th>name</th><th>address</th><th>state</th><th></th></tr>
    </thead>
    <tbody>
      {#each tableNodes as node (node.id)}
        <tr
          id={`${TABLE_ROW_ID_PREFIX}${node.id}`}
          class="row row-{node.state}"
          class:selected={selectedId === node.id}
          onclick={() => { selectRow(node.id); scrollToRow(node.id) }}
        >
          <td class="col-icon"><img src={iconPath(node)} alt="" width="24" height="24" /></td>
          <td class="col-name">{node.label}</td>
          <td class="col-address">{node.subtitle}</td>
          <td class="col-state"><span class="dot {node.state}"></span>{STATE_LABELS[node.state]}</td>
          <td class="col-open"><a class="btn line sm" href={machineHrefFor(node)}>Open</a></td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<div class="legend">
  <span><span class="legenddot online"></span>online</span>
  <span><span class="legenddot setup"></span>needs setup</span>
  <span><span class="legenddot offline"></span>offline</span>
  <span class="kinds"><span class="k mesh">—</span> mesh tunnel &nbsp; <span class="k ssh">—</span> ssh &nbsp; <span class="k public">—</span> public</span>
  <span class="hint">drag canvas to pan · wheel to zoom · drag a machine to move it · click to select · double-click to open</span>
</div>

<style>
  .map { display: block; margin-top: 8px; width: 100%; max-width: 960px; height: 560px; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; touch-action: none; user-select: none; }
  .map.grabbing { cursor: grabbing; }
  .map:not(.grabbing) { cursor: grab; }
  .node { cursor: grab; }
  .node:hover .tile { stroke: var(--accent); }
  .node.selected .tile { stroke: var(--accent); stroke-width: 2; }
  .tile { fill: var(--surface); stroke: var(--line); }
  .node-online .statedot { fill: var(--ok); }
  .node-setup .statedot { fill: var(--warn); }
  .node-offline .statedot { fill: var(--off); }
  .label { fill: var(--text); font-size: 12px; font-weight: 500; text-anchor: middle; }
  .sub { fill: var(--muted); font-size: 11px; text-anchor: middle; }
  .edge { stroke: var(--line); stroke-width: 1.5; }
  .edge-mesh { stroke: var(--accent-mark); }
  .edge-ssh { stroke: var(--info); }
  .edge-public { stroke: var(--m40); stroke-dasharray: 2 4; }
  .statedot { stroke: var(--surface); stroke-width: 1.5; }
  .mapcontrols { position: absolute; right: 18px; top: 18px; display: flex; flex-direction: column; gap: 6px; }
  .mapcontrols button { width: 32px; height: 32px; border: 1px solid var(--line); background: var(--surface); color: var(--text); border-radius: 6px; cursor: pointer; font-size: 15px; line-height: 1; }
  .mapcontrols button:hover { border-color: var(--accent); color: var(--accent-d); }
  .zoomlevel { font-size: 10px; color: var(--muted); text-align: center; }
  .machinetable-wrap { margin-top: 10px; width: 100%; max-width: 960px; max-height: 240px; overflow-y: auto; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); }
  .machinetable { width: 100%; border-collapse: collapse; font-size: 13px; color: var(--text); }
  .machinetable th { position: sticky; top: 0; background: var(--surface); text-align: left; padding: 6px 12px; font-size: 11px; font-weight: 500; color: var(--muted); border-bottom: 1px solid var(--line); }
  .machinetable td { padding: 5px 12px; border-bottom: 1px solid var(--line); }
  .machinetable tbody tr:last-child td { border-bottom: none; }
  .row { cursor: pointer; height: 32px; }
  .row:hover { background: var(--surface-2); }
  .row.selected { background: var(--surface-2); box-shadow: inset 3px 0 0 var(--accent); }
  .row.selected .col-name { color: var(--accent); }
  .col-icon { width: 40px; }
  .col-icon img { display: block; border-radius: 4px; }
  .col-name { font-weight: 500; }
  .col-address { color: var(--muted); }
  .col-state { color: var(--text); white-space: nowrap; }
  .col-open { text-align: right; }
  .col-open a { pointer-events: auto; }
  .dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }
  .dot.online { background: var(--ok); }
  .dot.setup { background: var(--warn); }
  .dot.offline { background: var(--off); }
  .legend { display: flex; gap: 14px; margin-top: 12px; font-size: 12px; color: var(--muted); flex-wrap: wrap; }
  .legend .legenddot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; }
  .legend .legenddot.online { background: var(--ok); }
  .legend .legenddot.setup { background: var(--warn); }
  .legend .legenddot.offline { background: var(--off); }
  .kinds { margin-left: 24px; }
  .k.mesh { color: var(--accent-mark); }
  .k.ssh { color: var(--info); }
  .k.public { color: var(--muted); }
  .hint { margin-left: auto; color: var(--m40); }
</style>
