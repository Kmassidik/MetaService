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
  .map { display: block; margin-top: 8px; width: 100%; max-width: 960px; height: 560px; background: #0e1319; border: 1px solid #1a222d; border-radius: 12px; }
  .node { cursor: pointer; }
  .node:hover .halo { opacity: 1; }
  .halo { opacity: 0; transition: opacity .15s; fill: none; }
  .node-online .halo { stroke: #2ea34a; stroke-opacity: .35; }
  .node-setup .halo { stroke: #d9971a; stroke-opacity: .35; }
  .node-offline .halo { stroke: #c04343; stroke-opacity: .35; }
  .label { fill: #dbe2ea; font-size: 12px; font-weight: 500; text-anchor: middle; }
  .sub { fill: #8b98a6; font-size: 11px; text-anchor: middle; }
  .edge { stroke: #33485e; stroke-width: 1.5; stroke-dasharray: 4 3; }
  .edge-mesh { stroke: #2ea34a; }
  .edge-ssh { stroke: #3f87d9; }
  .edge-public { stroke: #7a8694; stroke-dasharray: 1 4; }
  .legend { display: flex; gap: 14px; margin-top: 12px; font-size: 12px; color: #8b98a6; }
  .dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; }
  .dot.online { background: #2ea34a; }
  .dot.setup { background: #d9971a; }
  .dot.offline { background: #c04343; }
  .kinds { margin-left: 24px; }
  .k.mesh { color: #2ea34a; }
  .k.ssh { color: #3f87d9; }
  .k.public { color: #7a8694; }
</style>
