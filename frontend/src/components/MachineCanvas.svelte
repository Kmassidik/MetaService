<script lang="ts">
  // Machines map: a 2D canvas engine. Pan/zoom/drag, animated packets on the edges, an in-canvas
  // legend bar, and an inspector drawer with real machine fields only (no invented telemetry).
  import { buildGraph, machineHrefFor, edgeKindFor } from '../lib/machineMap.ts'
  import type { CanvasNode, MapIconKind } from '../lib/machineMap.ts'
  import type { Machine } from '../lib/types.ts'

  let { machines, hub, query = $bindable('') }: { machines: Machine[]; hub: string; query?: string } = $props()

  const MIN_ZOOM = 0.45
  const MAX_ZOOM = 2.2
  const ZOOM_STEP = 1.1
  const CLICK_MS = 350
  const NODE_HIT = 28
  const NODE_HIT_LABEL = 14
  const PACKET_COUNT = 3

  type EdgeKind = 'mesh' | 'ssh' | 'public'
  const EDGE_COLOR: Record<EdgeKind, string> = { mesh: '#4E8241', ssh: '#3B6998', public: '#9CA3AF' }
  const STATE_COLOR: Record<CanvasNode['state'], string> = { online: '#3B7A3E', setup: '#D97706', offline: '#9CA3AF' }

  interface Packet {
    edgeIndex: number
    progress: number
    speed: number
    forward: boolean
  }

  let canvasEl: HTMLCanvasElement | undefined = $state()
  let containerEl: HTMLDivElement | undefined = $state()
  let selectedId = $state<string | null>(null)
  let showTraffic = $state(true)
  let pingNodeId = $state<string | null>(null)
  let pingTime = 0
  let zoomLabel = $state('100%')
  let hoveredId: string | null = null

  // Camera
  let camX = 0
  let camY = 0
  let zoom = 1
  // Drag/pan state (not reactive; only read inside pointer handlers and the render loop)
  let dragNodeId: string | null = null
  let dragOffset = { x: 0, y: 0 }
  let panning = false
  let panStart = { x: 0, y: 0 }
  let moved = false
  let lastClickTime = 0
  let lastClickId: string | null = null
  let packets: Packet[] = []

  const graph = $derived.by(() => {
    const built = buildGraph(machines, hub)
    // Keep dragged positions across data refreshes.
    for (const node of built.nodes) {
      const saved = savedPositions[node.id]
      if (saved) {
        node.x = saved.x
        node.y = saved.y
      }
    }
    return built
  })

  let savedPositions: Record<string, { x: number; y: number }> = loadPositions()

  function loadPositions(): Record<string, { x: number; y: number }> {
    try {
      return JSON.parse(localStorage.getItem('ms-map-positions') ?? '{}') as Record<string, { x: number; y: number }>
    } catch {
      return {}
    }
  }

  function savePositions(): void {
    const all: Record<string, { x: number; y: number }> = {}
    for (const node of graph.nodes) all[node.id] = { x: node.x, y: node.y }
    localStorage.setItem('ms-map-positions', JSON.stringify(all))
  }

  function nodeById(id: string): CanvasNode | undefined {
    return graph.nodes.find((n) => n.id === id)
  }

  /** A machine matches when the route query (?q=) names it; non-matching nodes dim. */
  function matchesQuery(node: CanvasNode): boolean {
    if (!query.trim()) return true
    return node.label.toLowerCase().includes(query.toLowerCase()) || node.subtitle.toLowerCase().includes(query.toLowerCase()) || node.state.includes(query.toLowerCase())
  }

  // --- coordinate transforms ---
  function worldToScreen(wx: number, wy: number): { x: number; y: number } {
    return { x: wx * zoom + containerEl!.clientWidth / 2 + camX, y: wy * zoom + containerEl!.clientHeight / 2 + camY }
  }

  function screenToWorld(sx: number, sy: number): { x: number; y: number } {
    return { x: (sx - containerEl!.clientWidth / 2 - camX) / zoom, y: (sy - containerEl!.clientHeight / 2 - camY) / zoom }
  }

  function applyZoom(next: number, fx?: number, fy?: number): void {
    const clamped = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, next))
    const width = containerEl!.clientWidth
    const height = containerEl!.clientHeight
    const fxv = fx ?? width / 2
    const fyv = fy ?? height / 2
    const before = screenToWorld(fxv, fyv)
    zoom = clamped
    const after = screenToWorld(fxv, fyv)
    camX += (after.x - before.x) * zoom
    camY += (after.y - before.y) * zoom
    zoomLabel = `${Math.round(zoom * 100)}%`
  }

  function resetView(): void {
    camX = 0
    camY = 0
    applyZoom(containerEl!.clientWidth < 640 ? 0.72 : 1)
  }

  function recenter(): void {
    savedPositions = {}
    localStorage.removeItem('ms-map-positions')
    for (const node of graph.nodes) {
      const saved = savedPositions[node.id]
      if (saved) {
        node.x = saved.x
        node.y = saved.y
      }
    }
    // rebuild from presets: easiest is to recompute from machines (graph is derived from them)
    resetView()
  }

  // --- hit testing ---
  function nodeAt(sx: number, sy: number): CanvasNode | undefined {
    const world = screenToWorld(sx, sy)
    for (let i = graph.nodes.length - 1; i >= 0; i--) {
      const node = graph.nodes[i]!
      const hit = node.isHub ? NODE_HIT + 4 : NODE_HIT
      if (Math.abs(world.x - node.x) <= hit && Math.abs(world.y - node.y) <= hit + NODE_HIT_LABEL) return node
    }
    return undefined
  }

  function pointerPos(event: PointerEvent | WheelEvent): { x: number; y: number } {
    const rect = canvasEl!.getBoundingClientRect()
    return { x: event.clientX - rect.left, y: event.clientY - rect.top }
  }

  // --- pointer handlers ---
  function onPointerDown(event: PointerEvent): void {
    try {
      canvasEl!.setPointerCapture(event.pointerId)
    } catch {
      // synthetic or already-gone pointer: interactions still work without capture
    }
    const pos = pointerPos(event)
    const hit = nodeAt(pos.x, pos.y)
    moved = false
    if (hit) {
      dragNodeId = hit.id
      const world = screenToWorld(pos.x, pos.y)
      dragOffset = { x: hit.x - world.x, y: hit.y - world.y }
      selectNode(hit.id)
    } else {
      panning = true
      panStart = { x: pos.x - camX, y: pos.y - camY }
    }
  }

  function onPointerMove(event: PointerEvent): void {
    const pos = pointerPos(event)
    if (dragNodeId) {
      const world = screenToWorld(pos.x, pos.y)
      const node = nodeById(dragNodeId)
      if (node) {
        node.x = world.x + dragOffset.x
        node.y = world.y + dragOffset.y
      }
      moved = true
      return
    }
    if (panning) {
      camX = pos.x - panStart.x
      camY = pos.y - panStart.y
      moved = true
      return
    }
    const hit = nodeAt(pos.x, pos.y)
    hoveredId = hit?.id ?? null
    canvasEl!.style.cursor = hit ? 'pointer' : 'grab'
  }

  function onPointerUp(event: PointerEvent): void {
    if (canvasEl!.hasPointerCapture(event.pointerId)) canvasEl!.releasePointerCapture(event.pointerId)
    if (dragNodeId) {
      savePositions()
      if (!moved) handleNodeClick(dragNodeId)
    }
    dragNodeId = null
    panning = false
  }

  function handleNodeClick(nodeId: string): void {
    const now = Date.now()
    if (lastClickId === nodeId && now - lastClickTime < CLICK_MS) {
      lastClickTime = 0
      lastClickId = null
      const node = nodeById(nodeId)
      if (node) location.hash = machineHrefFor(node.machineId)
      return
    }
    lastClickTime = now
    lastClickId = nodeId
    selectNode(nodeId)
  }

  function onWheel(event: WheelEvent): void {
    event.preventDefault()
    const pos = pointerPos(event)
    applyZoom(zoom * (event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP), pos.x, pos.y)
  }

  // --- inspector ---
  const selected = $derived(selectedId ? machines.find((m) => m.id === selectedId) ?? null : null)
  const selectedNode = $derived(selectedId ? nodeById(selectedId) ?? null : null)

  function selectNode(id: string): void {
    selectedId = id
  }

  function ping(): void {
    pingNodeId = selectedId
    pingTime = performance.now()
  }

  function copyIp(): void {
    if (!selected?.ip) return
    void navigator.clipboard.writeText(selected.ip)
  }

  // --- rendering ---
  let rafId = 0

  function draw(timestamp: number): void {
    const canvas = canvasEl
    const container = containerEl
    if (!canvas || !container) return
    const dpr = window.devicePixelRatio || 1
    const width = container.clientWidth
    const height = container.clientHeight
    if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
      canvas.width = Math.round(width * dpr)
      canvas.height = Math.round(height * dpr)
    }
    const ctx = canvas.getContext('2d')!
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, width, height)

    drawGrid(ctx, width, height)

    // edges
    graph.edges.forEach((edge, index) => {
      const from = nodeById(edge.fromId)
      const to = nodeById(edge.toId)
      if (!from || !to) return
      const p1 = worldToScreen(from.x, from.y)
      const p2 = worldToScreen(to.x, to.y)
      const highlighted = hoveredId === from.id || hoveredId === to.id || selectedId === from.id || selectedId === to.id
      const dimmed = !matchesQuery(from) && !matchesQuery(to)
      ctx.save()
      ctx.beginPath()
      ctx.moveTo(p1.x, p1.y)
      ctx.lineTo(p2.x, p2.y)
      if (edge.kind === 'public') ctx.setLineDash([5 * zoom, 5 * zoom])
      ctx.strokeStyle = highlighted ? EDGE_COLOR[edge.kind] : '#C9CCC9'
      ctx.lineWidth = (highlighted ? 2.4 : 1.5) * Math.max(0.75, zoom)
      ctx.globalAlpha = dimmed ? 0.15 : 0.9
      ctx.stroke()
      ctx.restore()

      // protocol badge at the midpoint when zoomed in or highlighted
      if ((zoom >= 0.9 || highlighted) && !dimmed) {
        const midX = (p1.x + p2.x) / 2
        const midY = (p1.y + p2.y) / 2
        const label = edge.kind
        ctx.font = `600 ${Math.round(9 * Math.max(0.85, zoom))}px "JetBrains Mono", monospace`
        const textW = ctx.measureText(label).width + 10
        const textH = 15 * Math.max(0.85, zoom)
        ctx.fillStyle = '#FFFFFF'
        ctx.strokeStyle = '#E4E7E4'
        ctx.lineWidth = 1
        ctx.setLineDash([])
        ctx.beginPath()
        ctx.roundRect(midX - textW / 2, midY - textH / 2, textW, textH, 4)
        ctx.fill()
        ctx.stroke()
        ctx.fillStyle = '#6B7280'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText(label, midX, midY + 0.5)
      }

      // animated packets
      if (showTraffic && !dimmed) {
        const packet = packets[index]
        if (packet) {
          packet.progress += packet.speed
          if (packet.progress > 1) packet.progress -= 1
          const t = packet.forward ? packet.progress : 1 - packet.progress
          const wx = from.x + (to.x - from.x) * t
          const wy = from.y + (to.y - from.y) * t
          const pos = worldToScreen(wx, wy)
          ctx.save()
          ctx.globalAlpha = 0.85
          ctx.beginPath()
          ctx.arc(pos.x, pos.y, 3 * Math.max(0.8, zoom), 0, Math.PI * 2)
          ctx.fillStyle = EDGE_COLOR[edge.kind]
          ctx.fill()
          ctx.restore()
        }
      }
    })

    // nodes
    for (const node of graph.nodes) {
      const pos = worldToScreen(node.x, node.y)
      const matched = matchesQuery(node)
      const isSelected = selectedId === node.id
      const isHovered = hoveredId === node.id
      const box = (node.isHub ? 52 : 44) * zoom
      const half = box / 2
      ctx.save()
      ctx.globalAlpha = matched ? 1 : 0.22

      // ping ripple
      if (pingNodeId === node.id) {
        const elapsed = (timestamp - pingTime) / 1000
        if (elapsed < 1.2) {
          ctx.beginPath()
          ctx.arc(pos.x, pos.y, half + elapsed * 45 * zoom, 0, Math.PI * 2)
          ctx.strokeStyle = `rgba(108, 166, 93, ${1 - elapsed / 1.2})`
          ctx.lineWidth = 2.5
          ctx.stroke()
        } else {
          pingNodeId = null
        }
      }

      // hub ambient ring
      if (node.isHub) {
        ctx.beginPath()
        ctx.arc(pos.x, pos.y, half + 10 * zoom, 0, Math.PI * 2)
        ctx.fillStyle = 'rgba(108, 166, 93, 0.08)'
        ctx.fill()
        ctx.strokeStyle = 'rgba(108, 166, 93, 0.35)'
        ctx.lineWidth = 1
        ctx.setLineDash([3, 3])
        ctx.stroke()
        ctx.setLineDash([])
      }

      // selection / hover ring
      if (isSelected || isHovered) {
        ctx.beginPath()
        ctx.roundRect(pos.x - half - 5 * zoom, pos.y - half - 5 * zoom, box + 10 * zoom, box + 10 * zoom, 12 * zoom)
        ctx.strokeStyle = isSelected ? '#4E8241' : '#9CA3AF'
        ctx.lineWidth = 2
        ctx.stroke()
      }

      // card
      ctx.shadowColor = 'rgba(0, 0, 0, 0.06)'
      ctx.shadowBlur = 10
      ctx.shadowOffsetY = 3
      ctx.fillStyle = '#FFFFFF'
      ctx.strokeStyle = isSelected ? '#4E8241' : node.isHub ? '#6CA65D' : '#D4D4D8'
      ctx.lineWidth = node.isHub ? 2 : 1.5
      ctx.beginPath()
      ctx.roundRect(pos.x - half, pos.y - half, box, half * 2, 10 * zoom)
      ctx.fill()
      ctx.shadowColor = 'transparent'
      ctx.stroke()

      drawHardwareIcon(ctx, node.icon, pos.x, pos.y, box * 0.62)

      // status dot
      const dotR = 4.2 * Math.max(0.75, zoom)
      const dotX = pos.x + half - 2 * zoom
      const dotY = pos.y - half + 2 * zoom
      ctx.beginPath()
      ctx.arc(dotX, dotY, dotR + 1.5, 0, Math.PI * 2)
      ctx.fillStyle = '#FFFFFF'
      ctx.fill()
      ctx.beginPath()
      ctx.arc(dotX, dotY, dotR, 0, Math.PI * 2)
      ctx.fillStyle = STATE_COLOR[node.state]
      ctx.fill()

      // labels
      const nameSize = Math.round(12 * Math.max(0.75, zoom))
      ctx.font = `600 ${nameSize}px "JetBrains Mono", monospace`
      ctx.fillStyle = '#18181B'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'top'
      const labelY = pos.y + half + 7 * zoom
      ctx.fillText(node.label, pos.x, labelY)
      const subSize = Math.round(10 * Math.max(0.75, zoom))
      ctx.font = `400 ${subSize}px "JetBrains Mono", monospace`
      ctx.fillStyle = '#5B5F5B'
      ctx.fillText(node.isHub ? `${node.subtitle}` : node.subtitle, pos.x, labelY + nameSize + 3 * zoom)
      ctx.restore()
    }

    rafId = requestAnimationFrame(draw)
  }

  function drawGrid(ctx: CanvasRenderingContext2D, width: number, height: number): void {
    const grid = 28 * zoom
    if (grid < 8) return
    ctx.fillStyle = '#E9ECE9'
    const offsetX = (width / 2 + camX) % grid
    const offsetY = (height / 2 + camY) % grid
    for (let x = offsetX; x < width; x += grid) {
      for (let y = offsetY; y < height; y += grid) {
        ctx.beginPath()
        ctx.arc(x, y, 1, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }

  /** Simple vector hardware glyphs (no external icon files needed on canvas). */
  function drawHardwareIcon(ctx: CanvasRenderingContext2D, kind: MapIconKind, x: number, y: number, size: number): void {
    ctx.save()
    ctx.translate(x, y)
    const s = size / 24
    ctx.scale(s, s)
    ctx.translate(-12, -12)
    ctx.lineWidth = 1.8
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    const shape: Record<MapIconKind, 'router' | 'gpu' | 'mini' | 'studio' | 'tower' | 'box'> = {
      hub: 'router', dgx: 'gpu', fedora: 'box', rtx5090: 'tower', macmini: 'mini', macmini2: 'mini', macstudio: 'studio', macstudio2: 'studio', cloud: 'box',
    }
    drawShape(ctx, shape[kind]!)
    ctx.restore()
  }

  function drawShape(ctx: CanvasRenderingContext2D, shape: 'router' | 'gpu' | 'mini' | 'studio' | 'tower' | 'box'): void {
    switch (shape) {
      case 'router': {
        ctx.fillStyle = '#1E293B'
        ctx.beginPath()
        ctx.roundRect(3, 11, 18, 7, 2)
        ctx.fill()
        ctx.strokeStyle = '#0F172A'
        ctx.beginPath()
        ctx.moveTo(7, 11)
        ctx.lineTo(6, 5)
        ctx.moveTo(12, 11)
        ctx.lineTo(12, 4)
        ctx.moveTo(17, 11)
        ctx.lineTo(18, 5)
        ctx.stroke()
        ctx.fillStyle = '#6CA65D'
        for (const led of [7, 10.5, 14]) {
          ctx.beginPath()
          ctx.arc(led, 14.5, 1, 0, Math.PI * 2)
          ctx.fill()
        }
        return
      }
      case 'gpu': {
        ctx.fillStyle = '#2E7D32'
        ctx.beginPath()
        ctx.roundRect(3, 6, 18, 12, 2)
        ctx.fill()
        ctx.fillStyle = '#111827'
        ctx.fillRect(6, 9, 6, 6)
        ctx.fillStyle = '#A7F3D0'
        ctx.fillRect(14, 9, 4, 2)
        ctx.fillRect(14, 13, 4, 2)
        return
      }
      case 'mini': {
        ctx.fillStyle = '#F3F4F6'
        ctx.strokeStyle = '#374151'
        ctx.beginPath()
        ctx.roundRect(3, 9, 18, 6, 2)
        ctx.fill()
        ctx.stroke()
        ctx.fillStyle = '#111827'
        ctx.fillRect(7, 12, 7, 1.2)
        ctx.fillStyle = '#6CA65D'
        ctx.beginPath()
        ctx.arc(17.5, 12, 0.9, 0, Math.PI * 2)
        ctx.fill()
        return
      }
      case 'studio': {
        ctx.fillStyle = '#E5E7EB'
        ctx.strokeStyle = '#374151'
        ctx.beginPath()
        ctx.roundRect(4, 6, 16, 12, 2.5)
        ctx.fill()
        ctx.stroke()
        ctx.fillStyle = '#1F2937'
        ctx.fillRect(7, 13.5, 4, 1.5)
        ctx.fillRect(13, 13.5, 4, 1.5)
        return
      }
      case 'tower': {
        ctx.fillStyle = '#1F2937'
        ctx.beginPath()
        ctx.roundRect(6, 3, 12, 18, 2)
        ctx.fill()
        ctx.strokeStyle = '#38BDF8'
        ctx.beginPath()
        ctx.moveTo(9, 7)
        ctx.lineTo(15, 7)
        ctx.moveTo(9, 10)
        ctx.lineTo(15, 10)
        ctx.stroke()
        return
      }
      case 'box': {
        ctx.fillStyle = '#F3F4F6'
        ctx.strokeStyle = '#374151'
        ctx.beginPath()
        ctx.roundRect(4, 7, 16, 11, 2)
        ctx.fill()
        ctx.stroke()
        return
      }
    }
  }

  // --- lifecycle ---
  $effect(() => {
    packets = graph.edges.map((_, i) => ({
      edgeIndex: i,
      progress: (i * 0.17) % 1,
      speed: 0.004 + (i % PACKET_COUNT) * 0.0015,
      forward: i % 2 === 0,
    }))
    rafId = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(rafId)
  })

  $effect(() => {
    // fit once on mount
    if (containerEl) resetView()
  })
</script>

<div class="canvaswrap" bind:this={containerEl}>
  <canvas
    bind:this={canvasEl}
    class="mapcanvas"
    aria-label="Machines map"
    onpointerdown={onPointerDown}
    onpointermove={onPointerMove}
    onpointerup={onPointerUp}
    onpointerleave={() => (hoveredId = null)}
    onwheel={onWheel}
  ></canvas>

  <div class="zoomcontrols">
    <button type="button" aria-label="Zoom in" onclick={() => applyZoom(zoom * 1.15)}>+</button>
    <button type="button" aria-label="Zoom out" onclick={() => applyZoom(zoom * 0.85)}>−</button>
    <button type="button" aria-label="Reset view" onclick={resetView}>⌂</button>
    <button type="button" aria-label="Re-center layout" onclick={recenter} title="Re-center layout">⟲</button>
    <span class="zoomlevel">{zoomLabel}</span>
  </div>

  <button type="button" class="trafficpill" class:off={!showTraffic} onclick={() => (showTraffic = !showTraffic)}>
    <span class="trafficdot" class:off={!showTraffic}></span> Live traffic
  </button>

  <div class="legendbar">
    <span class="legend"><span class="dot" style="background:{STATE_COLOR.online}"></span>online</span>
    <span class="legend"><span class="dot" style="background:{STATE_COLOR.setup}"></span>needs setup</span>
    <span class="legend"><span class="dot" style="background:{STATE_COLOR.offline}"></span>offline</span>
    <span class="sep">|</span>
    <span class="legend"><span class="line" style="background:{EDGE_COLOR.mesh}"></span>mesh tunnel</span>
    <span class="legend"><span class="line" style="background:{EDGE_COLOR.ssh}"></span>ssh</span>
    <span class="legend"><span class="line dashed" style="border-color:{EDGE_COLOR.public}"></span>public</span>
    <span class="hint">drag canvas to pan · wheel to zoom · drag a machine to move · click to inspect · double-click to open</span>
  </div>

  {#if selected && selectedNode}
    <aside class="drawer" aria-label="Machine inspector">
      <header>
        <div>
          <div class="titlerow">
            <span class="dot big" style="background:{STATE_COLOR[selectedNode.state]}"></span>
            <h2>{selected.name}</h2>
          </div>
          <p class="role">{selectedNode.isHub ? 'hub · parent' : selected.engine ?? selected.arch}</p>
        </div>
        <button type="button" aria-label="Close inspector" onclick={() => (selectedId = null)}>✕</button>
      </header>
      <dl>
        <div><dt>Address</dt><dd><button type="button" class="copy" onclick={copyIp} disabled={!selected.ip}>{selected.ip ?? '—'}</button></dd></div>
        <div><dt>OS</dt><dd>{selected.os} · {selected.arch}</dd></div>
        <div><dt>Link</dt><dd>{edgeKindFor(selected)}</dd></div>
        <div><dt>Helper</dt><dd>{selected.agent_version ?? '—'}</dd></div>
        <div><dt>RAM</dt><dd>{selected.ram_total_mb ? `${Math.round(selected.ram_total_mb / 1024)} GB` : '—'}</dd></div>
        <div><dt>CPU</dt><dd>{selected.cpu_model ?? `${selected.cpu_cores ?? '—'} cores`}</dd></div>
        {#if (selected.problems?.length ?? 0) > 0}
          <div class="problems"><dt>Problems</dt><dd>{(selected.problems ?? []).map((p) => p.code).join(', ')}</dd></div>
        {/if}
      </dl>
      <footer>
        <button type="button" class="action primary" onclick={ping}>Ping node</button>
        <a class="action" href={machineHrefFor(selected.id)}>Open machine page</a>
      </footer>
    </aside>
  {/if}
</div>

<style>
  .canvaswrap { position: relative; width: 100%; height: 620px; border: 1px solid var(--line); border-radius: 12px; background: #fafafa; overflow: hidden; }
  .mapcanvas { display: block; width: 100%; height: 100%; touch-action: none; cursor: grab; }
  .zoomcontrols { position: absolute; top: 16px; right: 16px; display: flex; flex-direction: column; align-items: center; gap: 6px; z-index: 5; }
  .zoomcontrols button { width: 34px; height: 34px; border: 1px solid var(--line); background: var(--surface); color: var(--text); border-radius: 8px; cursor: pointer; font-size: 15px; line-height: 1; box-shadow: 0 1px 3px rgba(0,0,0,0.06); }
  .zoomcontrols button:hover { border-color: var(--accent); }
  .zoomlevel { font-size: 10px; color: var(--muted); background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 1px 6px; }
  .trafficpill { position: absolute; top: 16px; left: 16px; display: inline-flex; align-items: center; gap: 6px; padding: 5px 10px; border: 1px solid var(--line); background: var(--surface); color: var(--text); border-radius: 8px; font-size: 11px; cursor: pointer; box-shadow: 0 1px 3px rgba(0,0,0,0.06); z-index: 5; }
  .trafficpill.off { color: var(--muted); }
  .trafficdot { width: 8px; height: 8px; border-radius: 50%; background: var(--ok); }
  .trafficdot.off { background: var(--off); }
  .legendbar { position: absolute; left: 12px; right: 12px; bottom: 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; padding: 7px 14px; border: 1px solid var(--line); border-radius: 10px; background: rgba(255,255,255,0.92); font-size: 11px; color: var(--muted); pointer-events: none; z-index: 4; }
  .legend { display: inline-flex; align-items: center; gap: 5px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
  .dot.big { width: 11px; height: 11px; }
  .line { width: 14px; height: 2px; display: inline-block; }
  .line.dashed { height: 0; border-top: 2px dashed; background: transparent !important; }
  .sep { color: var(--line); }
  .hint { margin-left: auto; color: var(--muted); font-size: 10px; }
  .drawer { position: absolute; top: 16px; left: 16px; bottom: 64px; width: 300px; max-width: calc(100% - 32px); background: var(--surface); border: 1px solid var(--line); border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.12); padding: 14px; display: flex; flex-direction: column; justify-content: space-between; z-index: 6; }
  .drawer header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 1px solid var(--line); padding-bottom: 10px; }
  .drawer h2 { font-size: 14px; margin: 0; }
  .titlerow { display: flex; align-items: center; gap: 7px; }
  .role { font-size: 11px; color: var(--muted); margin: 3px 0 0; }
  .drawer header button { border: none; background: transparent; color: var(--muted); cursor: pointer; font-size: 13px; }
  .drawer dl { font-size: 12px; margin: 10px 0; }
  .drawer dl > div { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px solid var(--line); }
  .drawer dt { color: var(--muted); }
  .drawer dd { margin: 0; font-weight: 500; }
  .copy { border: none; background: transparent; color: var(--text); font: inherit; font-weight: 600; cursor: pointer; padding: 0; }
  .copy:hover { color: var(--accent); }
  .problems dd { color: var(--warn); }
  .drawer footer { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; border-top: 1px solid var(--line); padding-top: 10px; }
  .action { display: inline-block; text-align: center; padding: 8px 10px; border: 1px solid var(--line); border-radius: 8px; font-size: 12px; color: var(--text); text-decoration: none; }
  .action.primary { background: var(--text); color: var(--surface); border-color: var(--text); cursor: pointer; }
  .action:hover { border-color: var(--accent); }
</style>
