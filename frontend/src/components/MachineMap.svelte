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
      <circle class="halo" r="40" />
      <image href="/assets/icons/{node.icon}.webp" x="-24" y="-24" width="48" height="48" />
      <text class="label" y="42">{node.label}</text>
      <text class="sub" y="57">{node.subtitle}</text>
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
  .map { display: block; margin-top: 8px; width: 100%; max-width: 960px; height: 560px; background: var(--surface-2); border: 1px solid var(--line); border-radius: 12px; }
  .node { cursor: pointer; }
  .node:hover .halo { opacity: 1; }
  .halo { opacity: 0; transition: opacity .15s; fill: none; }
  .node-online .halo { stroke: var(--ok); stroke-opacity: .35; }
  .node-setup .halo { stroke: var(--warn); stroke-opacity: .45; }
  .node-offline .halo { stroke: var(--off); stroke-opacity: .45; }
  .label { fill: var(--text); font-size: 12px; font-weight: 500; text-anchor: middle; }
  .sub { fill: var(--m40); font-size: 11px; text-anchor: middle; }
  .edge { stroke: var(--line); stroke-width: 1.5; }
  .edge-mesh { stroke: var(--ok); }
  .edge-ssh { stroke: var(--info); }
  .edge-public { stroke: var(--m40); stroke-dasharray: 2 4; }
  .legend { display: flex; gap: 14px; margin-top: 12px; font-size: 12px; color: var(--m40); }
  .dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; }
  .dot.online { background: var(--ok); }
  .dot.setup { background: var(--warn); }
  .dot.offline { background: var(--off); }
  .kinds { margin-left: 24px; }
  .k.mesh { color: var(--ok); }
  .k.ssh { color: var(--info); }
  .k.public { color: var(--m40); }
</style>
