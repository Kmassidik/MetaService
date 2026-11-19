<script lang="ts">
  import { layout, machineHrefFor } from '../lib/machineMap.ts'
  import type { Machine } from '../lib/types.ts'

  let { machines, hub }: { machines: Machine[]; hub: string } = $props()
  const graph = $derived(layout(machines, hub))
</script>

  <svg viewBox="0 0 960 560" class="map" role="img" aria-label="Machines map">
  {#each graph.edges as edge}
    <line class="edge edge-{edge.kind}" x1={edge.from.x} y1={edge.from.y} x2={edge.to.x} y2={edge.to.y} />
  {/each}
  {#each graph.nodes as node (node.id)}
    <g class="node node-{node.state}" transform="translate({node.x},{node.y})" onclick={() => (location.hash = machineHrefFor(node))} role="link" tabindex="0" onkeydown={(e) => e.key === 'Enter' && (location.hash = machineHrefFor(node))}>
      <rect class="halo" x="-38" y="-34" width="76" height="76" rx="10" />
      <rect class="tile" x="-34" y="-30" width="68" height="68" rx="8" />
      <image href="/assets/icons/{node.icon}.webp" x="-24" y="-24" width="48" height="48" />
      <text class="label" y="52">{node.label}</text>
      <text class="sub" y="67">{node.subtitle}</text>
      <circle class="statedot" cx="24" cy="-24" r="5" />
    </g>
  {/each}
</svg>

<div class="legend">
  <span><span class="dot online"></span>online</span>
  <span><span class="dot setup"></span>needs setup</span>
  <span><span class="dot offline"></span>offline</span>
  <span class="kinds"><span class="k mesh">—</span> mesh tunnel &nbsp; <span class="k ssh">—</span> ssh &nbsp; <span class="k public">—</span> public</span>
</div>

<style>
  .map { display: block; margin-top: 8px; width: 100%; max-width: 960px; height: 560px; background: var(--surface); border: 1px solid var(--line); border-radius: 12px; }
  .node { cursor: pointer; }
  .node:hover .halo { opacity: 1; }
  .halo { opacity: 0; transition: opacity .15s; fill: var(--surface-2); stroke: var(--accent); }
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
  .legend { display: flex; gap: 14px; margin-top: 12px; font-size: 12px; color: var(--muted); }
  .dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; }
  .dot.online { background: var(--ok); }
  .dot.setup { background: var(--warn); }
  .dot.offline { background: var(--off); }
  .kinds { margin-left: 24px; }
  .k.mesh { color: var(--accent-mark); }
  .k.ssh { color: var(--info); }
  .k.public { color: var(--muted); }
</style>
